// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順5: ログイン画面が実際のGoogleログイン導線になっているか
// を自動再現するテスト。
//
// 期待される結果:
//   - ログイン画面に Google Identity Services のボタンが表示される
//   - ID トークンの貼り付け欄は表示されない
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step5_login_validation

import { render, screen } from "@testing-library/react";
import { AppShell } from "@/components/AppShell";
import LoginPage from "@/app/login/page";

function mockGoogleIdentityServices() {
  const renderButton = jest.fn((container: HTMLElement) => {
    container.replaceChildren();

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Googleでログイン";
    container.appendChild(button);
  });
  const initialize = jest.fn();

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

describe("PR45 手順5: ログイン画面が実際のGoogleログイン導線になっているか", () => {
  afterEach(() => {
    delete (window as typeof window & { google?: unknown }).google;
  });

  it("Google Identity Services のボタンが表示される", () => {
    mockGoogleIdentityServices();

    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    expect(screen.getByRole("button", { name: "Googleでログイン" })).toBeInTheDocument();
  });

  it("ID トークンの貼り付け欄は表示されない", () => {
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    expect(screen.getByRole("heading", { name: /Googleアカウントでログインします/ })).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).not.toBeInTheDocument();
  });
});
