let proxyRequest: typeof import("@/lib/api-proxy").proxyRequest;

class MockResponse {
  body: string;
  status: number;
  headers: Headers;

  constructor(body?: BodyInit | null, init?: ResponseInit) {
    const status = init?.status ?? 200;

    if ([204, 205, 304].includes(status) && body !== null) {
      throw new TypeError(`Response constructor: Invalid response status code ${status}`);
    }

    this.body = typeof body === "string" ? body : "";
    this.status = status;
    this.headers = new Headers(init?.headers);
  }

  async text() {
    return this.body;
  }

  static json(data: unknown, init?: ResponseInit) {
    return new MockResponse(JSON.stringify(data), {
      ...init,
      headers: {
        "content-type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
  }
}

describe("API proxy", () => {
  const originalEnv = process.env;

  beforeAll(async () => {
    (globalThis as typeof globalThis & { Response: typeof MockResponse }).Response = MockResponse;
    ({ proxyRequest } = await import("@/lib/api-proxy"));
  });

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      BACKEND_API_URL: "http://rails.internal",
      INTERNAL_API_SECRET: "shared-secret",
      NODE_ENV: "test",
    };

    global.fetch = jest.fn();
  });

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  it("forwards requests to Rails and issues a session cookie", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({
        "content-type": "application/json",
      }),
      text: async () =>
        JSON.stringify({ session_token: "signed-token", user: { id: 7, google_sub: "google-sub" } }),
    });

    const request = {
      method: "POST",
      url: "http://localhost:3000/api/v1/session?locale=ja",
      headers: new Headers({
        "content-type": "application/json",
        cookie: "parametric_session_token=existing-token",
        origin: "http://localhost:3000",
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [targetUrl, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(String(targetUrl)).toBe("http://rails.internal/api/v1/session?locale=ja");
    expect(init.method).toBe("POST");
    expect(init.cache).toBe("no-store");
    expect(init.headers.get("X-Internal-API-Secret")).toBe("shared-secret");
    expect(init.headers.get("X-Internal-Session-Token")).toBe("existing-token");
    expect(init.headers.get("cookie")).toBeNull();
    expect(response.headers.get("set-cookie")).toContain("parametric_session_token=signed-token");
  });

  it("returns a null body for 204 No Content responses", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 204,
      headers: new Headers(),
      text: async () => "",
    });

    const request = {
      method: "DELETE",
      url: "http://localhost:3000/api/v1/session",
      headers: new Headers({
        origin: "http://localhost:3000",
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(204);
    expect(response.body).toBe("");
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it("rejects state-changing requests with invalid Origin header with 403 Forbidden", async () => {
    const request = {
      method: "POST",
      url: "http://localhost:3000/api/v1/session",
      headers: new Headers({
        "content-type": "application/json",
        origin: "http://malicious.com",
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(403);
    expect(JSON.parse(response.body).error).toBe("Forbidden");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects state-changing requests without Origin header with 403 Forbidden", async () => {
    const request = {
      method: "POST",
      url: "http://localhost:3000/api/v1/session",
      headers: new Headers({
        "content-type": "application/json",
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(403);
    expect(JSON.parse(response.body).error).toBe("Forbidden");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects session creation request with non-JSON Content-Type with 415 Unsupported Media Type", async () => {
    const request = {
      method: "POST",
      url: "http://localhost:3000/api/v1/session",
      headers: new Headers({
        "content-type": "application/x-www-form-urlencoded",
        origin: "http://localhost:3000",
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(415);
    expect(JSON.parse(response.body).error).toBe("Unsupported Media Type");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects state-changing requests whose Origin scheme differs from the request's protocol with 403 Forbidden", async () => {
    const request = {
      method: "POST",
      url: "https://example.com/api/v1/session",
      headers: new Headers({
        "content-type": "application/json",
        origin: "http://example.com",
        host: "example.com",
        "x-forwarded-proto": "https",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(403);
    expect(JSON.parse(response.body).error).toBe("Forbidden");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects session creation request whose Content-Type is only a CORS-safelisted prefix match with 415 Unsupported Media Type", async () => {
    const request = {
      method: "POST",
      url: "http://localhost:3000/api/v1/session",
      headers: new Headers({
        "content-type": "text/plain;foo=application/json",
        origin: "http://localhost:3000",
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(415);
    expect(JSON.parse(response.body).error).toBe("Unsupported Media Type");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects path segments containing '..' with 404 Not Found instead of forwarding them upstream", async () => {
    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/../../rails/info/routes",
      headers: new Headers({
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "..", "..", "rails", "info", "routes"]);

    expect(response.status).toBe(404);
    expect(JSON.parse(response.body).error).toBe("Not Found");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects a path segment that is exactly '.' with 404 Not Found", async () => {
    const request = {
      method: "GET",
      url: "http://localhost:3000/api/./v1/session",
      headers: new Headers({
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, [".", "v1", "session"]);

    expect(response.status).toBe(404);
    expect(JSON.parse(response.body).error).toBe("Not Found");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("rejects double-encoded '..' segments (%252e%252e) that decode to traversal after Next.js's single decode pass", async () => {
    // Next.js decodes the raw request URL's `%252e%252e` segment once before handing it
    // to the route handler, so the value observed here is the once-decoded "%2e%2e".
    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/%252e%252e/%252e%252e/rails/info/routes",
      headers: new Headers({
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, [
      "v1",
      "%2e%2e",
      "%2e%2e",
      "rails",
      "info",
      "routes",
    ]);

    expect(response.status).toBe(404);
    expect(JSON.parse(response.body).error).toBe("Not Found");
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("re-encodes forwarded path segments so a literal '%2e%2e' segment cannot be normalized into a traversal by the URL parser", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => JSON.stringify({}),
    });

    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/%2e%2efoo",
      headers: new Headers({
        host: "localhost:3000",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    await proxyRequest(request, ["v1", "%2e%2efoo"]);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [targetUrl] = (global.fetch as jest.Mock).mock.calls[0];
    expect(String(targetUrl)).toBe("http://rails.internal/api/v1/%252e%252efoo");
  });

  it("does not forward a client-supplied X-Internal-Session-Token header when no session cookie is present", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => JSON.stringify({}),
    });

    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/policies",
      headers: new Headers({
        host: "localhost:3000",
        "x-internal-session-token": "forged-by-client",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    await proxyRequest(request, ["v1", "policies"]);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(init.headers.get("X-Internal-Session-Token")).toBeNull();
  });

  it("does not pick up a decoy cookie whose name merely ends with the session cookie name", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => JSON.stringify({}),
    });

    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/policies",
      headers: new Headers({
        host: "localhost:3000",
        cookie: "evil_parametric_session_token=decoy; parametric_session_token=real-token",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    await proxyRequest(request, ["v1", "policies"]);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(init.headers.get("X-Internal-Session-Token")).toBe("real-token");
  });

  it("skips an empty-valued session cookie and uses a later same-named cookie that has a value", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      text: async () => JSON.stringify({}),
    });

    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/policies",
      headers: new Headers({
        host: "localhost:3000",
        cookie: "parametric_session_token=; parametric_session_token=real-token",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    await proxyRequest(request, ["v1", "policies"]);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(init.headers.get("X-Internal-Session-Token")).toBe("real-token");
  });
});
