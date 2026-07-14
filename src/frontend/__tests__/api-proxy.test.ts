let proxyRequest: typeof import("@/lib/api-proxy").proxyRequest;

class MockResponse {
  body: string;
  status: number;
  headers: Headers;

  constructor(body?: BodyInit | null, init?: ResponseInit) {
    this.body = typeof body === "string" ? body : "";
    this.status = init?.status ?? 200;
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
    expect(response.headers.get("set-cookie")).toContain("parametric_session_token=signed-token");
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
});
