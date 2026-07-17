// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文の「セキュリティレビューを受けて対応した内容」に列挙された6項目について、
// BFF（src/frontend/lib/api-proxy.ts の proxyRequest）が実際にその対策を実装しているかを
// OWASP Top 10 (2021) の該当カテゴリに対応付けて確認する（@.claude/OWASP10.md 参照）。
//
// このテストは開発サーバーには接続せず、Next.js の Route Handler が呼び出す
// proxyRequest() をユニットテストとして直接呼び出し、global.fetch をモックして確認する。
// 本番サーバーには一切接続しない。
//
// 対応関係:
//   PR本文 対応項目1（二重エンコードのパストラバーサル拒否）      -> OWASP A03 Injection / A05 Security Misconfiguration
//   PR本文 対応項目2（内部専用ヘッダーのなりすまし防止）          -> OWASP A01 Broken Access Control / A07 Identification and Authentication Failures
//   PR本文 対応項目3（Cookie名の厳密な読み取り、偽名Cookie対策）  -> OWASP A07 Identification and Authentication Failures
//   PR本文 対応項目4（Railsへ転送する情報の最小化、生Cookie除去） -> OWASP A02 Cryptographic Failures / A01 Broken Access Control（最小権限）
//   PR本文 対応項目6（空Cookieの後ろにある有効トークンを拾えない不具合） -> OWASP A07 Identification and Authentication Failures
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_owasp_security_review_fixes

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
      headers: { "content-type": "application/json", ...(init?.headers ?? {}) },
    });
  }
}

describe("PR45 OWASP10確認: セキュリティレビュー対応事項がBFFに実装されている", () => {
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

  it("[A03/A05] 対応項目1: 二重エンコードされた '..' セグメント（%252e%252e）を使ったパストラバーサルを404で拒否する", async () => {
    const request = {
      method: "GET",
      url: "http://localhost:3000/api/v1/%252e%252e/%252e%252e/rails/info/routes",
      headers: new Headers({ host: "localhost:3000" }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "%2e%2e", "%2e%2e", "rails", "info", "routes"]);

    expect(response.status).toBe(404);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("[A01/A07] 対応項目2: クライアントが送りつけた偽の X-Internal-Session-Token ヘッダーは無視され、Railsへ転送されない", async () => {
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
        "x-internal-session-token": "attacker-forged-admin-token",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    await proxyRequest(request, ["v1", "policies"]);

    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(init.headers.get("X-Internal-Session-Token")).toBeNull();
  });

  it("[A07] 対応項目3: セッションCookie名の末尾一致だけで誤反応する偽装Cookie（evil_parametric_session_token）を拾わない", async () => {
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

    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(init.headers.get("X-Internal-Session-Token")).toBe("real-token");
  });

  it("[A01/A02] 対応項目4: Railsへ転送するリクエストから生のブラウザCookieヘッダーが取り除かれている（最小限の情報のみ転送）", async () => {
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
        cookie: "parametric_session_token=real-token; unrelated_marketing_cookie=tracking-id-123",
      }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    await proxyRequest(request, ["v1", "policies"]);

    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    // 生のcookieヘッダーは転送されず、署名済みセッションだけがX-Internal-Session-Tokenとして渡る
    expect(init.headers.get("cookie")).toBeNull();
    expect(init.headers.get("X-Internal-Session-Token")).toBe("real-token");
  });

  it("[A07] 対応項目6: 値が空の同名Cookieの後ろにある有効なセッションCookieを正しく拾う", async () => {
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

    const [, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(init.headers.get("X-Internal-Session-Token")).toBe("real-token");
  });

  it("[A05] CSRF対策: Originヘッダーがないstate変更リクエスト（POST）は403で拒否される", async () => {
    const request = {
      method: "POST",
      url: "http://localhost:3000/api/v1/session",
      headers: new Headers({ "content-type": "application/json", host: "localhost:3000" }),
      arrayBuffer: async () => new ArrayBuffer(0),
    } as unknown as Request;

    const response = await proxyRequest(request, ["v1", "session"]);

    expect(response.status).toBe(403);
    expect(global.fetch).not.toHaveBeenCalled();
  });
});
