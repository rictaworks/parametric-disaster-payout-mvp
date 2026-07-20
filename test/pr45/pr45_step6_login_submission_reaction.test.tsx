// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順6: セッション作成を試したときの画面反応
// を自動再現するテスト。
//
// 期待される結果（PR本文より）:
//   - ボタンを押すと一瞬「送信中」という表示になる
//   - バックエンド（Rails）が起動していない/エラーを返す開発環境では
//     「ログインに失敗しました。」という案内文が表示される（これは正常な反応）
//   - 有効なGoogle IDトークンで、Railsが応答する場合は「ログインに成功しました。」が表示される
// 本当の失敗パターン:
//   - ボタンを押した後、画面が固まって何も表示が変わらない
//   - 生々しいエラーコード（スタックトレースなど）がそのまま画面に表示される
//   - 「送信中」の表示から一切変化しない
//
// このテストは開発サーバーには接続せず、global.fetch をモックしてブラウザ操作
// （React コンポーネント）の挙動のみを検証する。本番サーバーには一切接続しない。
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step6_login_submission_reaction

import { act, render, screen, waitFor } from "@testing-library/react";
import { AppShell } from "@/components/AppShell";
import LoginPage from "@/app/login/page";
import ja from "@/locales/ja.json";

let gisCallback: ((response: { credential?: string }) => void) | undefined;

function mockGoogleIdentityServices() {
  gisCallback = undefined;
  const renderButton = jest.fn((container: HTMLElement) => {
    container.replaceChildren();

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Googleでログイン";
    container.appendChild(button);
  });
  const initialize = jest.fn((options: { callback: (response: { credential?: string }) => void }) => {
    gisCallback = options.callback;
  });

  (window as typeof window & {
    google?: {
      accounts?: {
        id?: {
          initialize: typeof initialize;
          renderButton: typeof renderButton;
        };
      };
    };
  }).google = {
    accounts: {
      id: {
        initialize,
        renderButton,
      },
    },
  };
}

describe("PR45 手順6: セッション作成を試したときの画面反応", () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    delete (window as typeof window & { google?: unknown }).google;
    gisCallback = undefined;
    jest.restoreAllMocks();
  });

  it("Railsサーバーが起動していない開発環境を模した場合（fetchが失敗）、「ログインに失敗しました。」が表示される", async () => {
    mockGoogleIdentityServices();
    global.fetch = jest.fn().mockRejectedValue(new TypeError("Failed to fetch"));

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    await waitFor(() => expect(gisCallback).toBeDefined());
    act(() => {
      gisCallback!({ credential: "test-token-12345" });
    });

    expect(await screen.findByText(ja.login.error)).toBeInTheDocument();
    expect(screen.getByText("ログインに失敗しました。")).toBeInTheDocument();
  });

  it("バックエンドがエラー応答を返す場合（401等）も「ログインに失敗しました。」が表示される", async () => {
    mockGoogleIdentityServices();
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      json: async () => ({ error: "invalid_token" }),
      text: async () => JSON.stringify({ error: "invalid_token" }),
    });

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    await waitFor(() => expect(gisCallback).toBeDefined());
    act(() => {
      gisCallback!({ credential: "test-token-12345" });
    });

    expect(await screen.findByText(ja.login.error)).toBeInTheDocument();
  });

  it("Railsが有効なGoogle IDトークンで成功応答を返す場合、「ログインに成功しました。」が表示される", async () => {
    mockGoogleIdentityServices();
    global.fetch = jest.fn().mockImplementation((_url, options) => {
      if (!options || options.method === "GET") {
        return Promise.resolve({
          ok: false,
          status: 401,
          json: async () => ({ error: "unauthorized" }),
          text: async () => JSON.stringify({ error: "unauthorized" }),
        });
      }
      return Promise.resolve({
        ok: true,
        status: 200,
        json: async () => ({ user: { id: 1 } }),
        text: async () => JSON.stringify({ user: { id: 1 } }),
      });
    });

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    await waitFor(() => expect(gisCallback).toBeDefined());
    act(() => {
      gisCallback!({ credential: "test-token-12345" });
    });

    expect(await screen.findByText(ja.login.success)).toBeInTheDocument();
    expect(screen.getByText("ログインに成功しました。")).toBeInTheDocument();
  });

  it("送信中は「送信中」表示になる", async () => {
    mockGoogleIdentityServices();
    let resolveFetch: (value: unknown) => void = () => undefined;
    global.fetch = jest.fn().mockImplementation((_url, options) => {
      if (!options || options.method === "GET") {
        return Promise.resolve({
          ok: false,
          status: 401,
          json: async () => ({ error: "unauthorized" }),
          text: async () => JSON.stringify({ error: "unauthorized" }),
        });
      }
      return new Promise((resolve) => {
        resolveFetch = resolve;
      });
    });

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    await waitFor(() => expect(gisCallback).toBeDefined());
    act(() => {
      gisCallback!({ credential: "test-token-12345" });
    });

    // 一瞬「送信中」という表示になる
    expect(await screen.findByText(ja.login.submitting)).toBeInTheDocument();

    // フェッチが解決すると、固まったままにならず表示が変化する
    resolveFetch({
      ok: true,
      status: 200,
      json: async () => ({ user: { id: 1 } }),
      text: async () => JSON.stringify({ user: { id: 1 } }),
    });

    await waitFor(() => {
      expect(screen.queryByText(ja.login.submitting)).not.toBeInTheDocument();
    });
    expect(await screen.findByText(ja.login.success)).toBeInTheDocument();
  });

  it("失敗時に生々しいスタックトレースやエラーオブジェクトの文字列がそのまま画面に表示されない", async () => {
    mockGoogleIdentityServices();
    global.fetch = jest.fn().mockRejectedValue(new TypeError("Failed to fetch"));

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    await waitFor(() => expect(gisCallback).toBeDefined());
    act(() => {
      gisCallback!({ credential: "test-token-12345" });
    });

    await screen.findByText(ja.login.error);

    const bodyText = document.body.textContent ?? "";
    expect(bodyText).not.toMatch(/TypeError/);
    expect(bodyText).not.toMatch(/at\s+\S+\s+\(.*:\d+:\d+\)/); // スタックトレース行の形式
    expect(bodyText).not.toMatch(/\[object Object\]/);
  });

  it("ログイン処理中にさらに credential callback が発火されても、多重送信を行わない", async () => {
    mockGoogleIdentityServices();
    let resolveFetch: (value: unknown) => void = () => undefined;
    const fetchMock = jest.fn().mockImplementation((_url, options) => {
      if (!options || options.method === "GET") {
        return Promise.resolve({
          ok: false,
          status: 401,
          json: async () => ({ error: "unauthorized" }),
          text: async () => JSON.stringify({ error: "unauthorized" }),
        });
      }
      return new Promise((resolve) => {
        resolveFetch = resolve;
      });
    });
    global.fetch = fetchMock;

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    await waitFor(() => expect(gisCallback).toBeDefined());

    // 1回目の発火
    act(() => {
      gisCallback!({ credential: "test-token-1" });
    });

    // 2回目の発火（1回目がまだ処理中の状態）
    act(() => {
      gisCallback!({ credential: "test-token-2" });
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);

    // 1回目を完了させる
    resolveFetch({
      ok: true,
      status: 200,
      json: async () => ({ user: { id: 1 } }),
      text: async () => JSON.stringify({ user: { id: 1 } }),
    });

    await waitFor(() => {
      expect(screen.queryByText(ja.login.submitting)).not.toBeInTheDocument();
    });

    // 完了後であれば、再度 callback を発火したときにリクエストが送信されること
    act(() => {
      gisCallback!({ credential: "test-token-3" });
    });
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });
});
