const SESSION_COOKIE_NAME = "parametric_session_token";

function getBackendBaseUrl() {
  const value = process.env.BACKEND_API_URL;

  if (!value) {
    throw new Error("BACKEND_API_URL is not configured");
  }

  return value;
}

function getInternalSecret() {
  const value = process.env.INTERNAL_API_SECRET;

  if (!value) {
    throw new Error("INTERNAL_API_SECRET is not configured");
  }

  return value;
}

function isSessionRoute(pathSegments: string[]) {
  return pathSegments.join("/") === "v1/session";
}

function verifyCsrf(request: Request): boolean {
  if (["GET", "HEAD", "OPTIONS"].includes(request.method)) {
    return true;
  }

  const origin = request.headers.get("origin");
  if (!origin) {
    return false;
  }

  const host = request.headers.get("x-forwarded-host") || request.headers.get("host");
  if (!host) {
    return false;
  }

  const forwardedProto = request.headers.get("x-forwarded-proto")?.split(",")[0]?.trim();
  const protocol = forwardedProto || (process.env.NODE_ENV === "production" ? "https" : "http");

  try {
    const originUrl = new URL(origin);
    const expectedOrigin = `${protocol}://${host}`;

    return originUrl.origin === expectedOrigin;
  } catch {
    return false;
  }
}

function isJsonContentType(contentType: string): boolean {
  const mediaType = contentType.split(";")[0]?.trim().toLowerCase();
  return mediaType === "application/json";
}

async function buildRequestBody(request: Request) {
  if (request.method === "GET" || request.method === "HEAD") {
    return undefined;
  }

  return await request.arrayBuffer();
}

function buildTargetUrl(pathSegments: string[], request: Request) {
  const target = new URL(getBackendBaseUrl());
  target.pathname = `/api/${pathSegments.join("/")}`;
  target.search = new URL(request.url).search;
  return target;
}

export async function proxyRequest(request: Request, pathSegments: string[]) {
  if (pathSegments.length === 0) {
    return Response.json({ error: "Not Found" }, { status: 404 });
  }

  if (!verifyCsrf(request)) {
    return Response.json({ error: "Forbidden" }, { status: 403 });
  }

  if (request.method === "POST" && isSessionRoute(pathSegments)) {
    const contentType = request.headers.get("content-type") || "";
    if (!isJsonContentType(contentType)) {
      return Response.json({ error: "Unsupported Media Type" }, { status: 415 });
    }
  }

  const targetUrl = buildTargetUrl(pathSegments, request);
  const headers = new Headers(request.headers);

  headers.delete("host");
  headers.delete("content-length");
  headers.set("X-Internal-API-Secret", getInternalSecret());

  const sessionToken = request.headers.get("cookie")?.match(/parametric_session_token=([^;]+)/)?.[1];
  if (sessionToken) {
    headers.set("X-Internal-Session-Token", sessionToken);
  }

  const backendResponse = await fetch(targetUrl, {
    method: request.method,
    headers,
    cache: "no-store",
    ...(request.method === "GET" || request.method === "HEAD"
      ? {}
      : {
          body: await buildRequestBody(request),
          duplex: "half" as const,
        }),
  });

  const responseBody = await backendResponse.text();
  const responseHeaders = new Headers(backendResponse.headers);
  responseHeaders.delete("content-length");
  responseHeaders.delete("transfer-encoding");
  responseHeaders.delete("connection");

  const responseHeadersWithCookies = new Headers(responseHeaders);
  let proxiedBody = responseBody;

  if (backendResponse.ok && isSessionRoute(pathSegments)) {
    try {
      const payload = JSON.parse(responseBody) as { session_token?: string };
      if (payload.session_token) {
        responseHeadersWithCookies.append(
          "Set-Cookie",
          [
            `${SESSION_COOKIE_NAME}=${payload.session_token}`,
            "HttpOnly",
            "Path=/",
            "SameSite=Lax",
            `Max-Age=${60 * 60 * 24 * 30}`,
            process.env.NODE_ENV === "production" ? "Secure" : null,
          ]
            .filter(Boolean)
            .join("; ")
        );

        const sanitizedPayload = { ...payload };
        delete sanitizedPayload.session_token;
        proxiedBody = JSON.stringify(sanitizedPayload);
      }
    } catch {
      // Keep the upstream response untouched when the body is not JSON.
    }
  }

  return new Response(proxiedBody, {
    status: backendResponse.status,
    headers: responseHeadersWithCookies,
  });
}
