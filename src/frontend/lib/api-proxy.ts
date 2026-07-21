const SESSION_COOKIE_NAME = "parametric_session_token";
const NULL_BODY_STATUSES = new Set([204, 205, 304]);

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

function canonicalDecodeSegment(segment: string): string {
  let previous = segment;

  for (let i = 0; i < 5; i += 1) {
    let current: string;
    try {
      current = decodeURIComponent(previous);
    } catch {
      return previous;
    }

    if (current === previous) {
      return current;
    }

    previous = current;
  }

  return previous;
}

function hasTraversalSegment(pathSegments: string[]) {
  return pathSegments.some((segment) => {
    const decoded = canonicalDecodeSegment(segment);
    return decoded === "." || decoded === "..";
  });
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

function extractSessionToken(request: Request): string | undefined {
  const cookieHeader = request.headers.get("cookie");
  if (!cookieHeader) {
    return undefined;
  }

  return cookieHeader
    .split(";")
    .map((pair) => pair.trim())
    .filter((pair) => pair.startsWith(`${SESSION_COOKIE_NAME}=`))
    .map((pair) => pair.slice(SESSION_COOKIE_NAME.length + 1))
    .find((tokenValue) => tokenValue.length > 0);
}

async function buildRequestBody(request: Request) {
  if (request.method === "GET" || request.method === "HEAD") {
    return undefined;
  }

  return await request.arrayBuffer();
}

function buildTargetUrl(pathSegments: string[], request: Request) {
  const target = new URL(getBackendBaseUrl());
  const encodedSegments = pathSegments.map((segment) => encodeURIComponent(segment));
  target.pathname = `/api/${encodedSegments.join("/")}`;
  target.search = new URL(request.url).search;

  if (!target.pathname.startsWith("/api/")) {
    throw new Error("Resolved target path escaped the /api/ boundary");
  }

  return target;
}

export async function proxyRequest(request: Request, pathSegments: string[]) {
  if (pathSegments.length === 0 || hasTraversalSegment(pathSegments)) {
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
  headers.delete("cookie");
  headers.delete("x-internal-session-token");
  headers.set("X-Internal-API-Secret", getInternalSecret());

  const sessionToken = extractSessionToken(request);
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
  responseHeaders.delete("content-encoding");
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

  return new Response(NULL_BODY_STATUSES.has(backendResponse.status) ? null : proxiedBody, {
    status: backendResponse.status,
    headers: responseHeadersWithCookies,
  });
}
