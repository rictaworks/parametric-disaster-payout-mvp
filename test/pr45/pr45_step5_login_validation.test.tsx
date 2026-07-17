// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順5: ログイン画面の入力チェックが機能しているか
// を自動再現するテスト。
//
// 期待される結果（PR本文より）:
//   - 「Google ID トークン」入力欄が空の状態では「セッションを作成」ボタンが無効化されている
//   - 入力欄に何か文字（例: "test-token-12345"）を入力するとボタンが押せるようになる
// 失敗パターン: 何も入力していないのにボタンが最初から押せる場合
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step5_login_validation

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "@/components/AppShell";
import LoginPage from "@/app/login/page";
import ja from "@/locales/ja.json";

describe("PR45 手順5: ログイン画面の入力チェックが機能しているか", () => {
  it("何も入力していない状態では「セッションを作成」ボタンが無効化されている", () => {
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    const submitButton = screen.getByRole("button", { name: ja.login.submit });
    expect(submitButton).toBeDisabled();
  });

  it("入力欄に文字を入力すると「セッションを作成」ボタンが押せるようになる", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    const input = screen.getByLabelText(ja.login.idTokenLabel);
    const submitButton = screen.getByRole("button", { name: ja.login.submit });

    expect(submitButton).toBeDisabled();

    await user.type(input, "test-token-12345");

    expect(submitButton).toBeEnabled();
  });

  it("空白文字だけを入力した場合はボタンが無効化されたままである（trim検証の確認）", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    const input = screen.getByLabelText(ja.login.idTokenLabel);
    const submitButton = screen.getByRole("button", { name: ja.login.submit });

    await user.type(input, "   ");

    expect(submitButton).toBeDisabled();
  });

  it("入力後に文字を全て削除するとボタンが再び無効化される", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    const input = screen.getByLabelText(ja.login.idTokenLabel);
    const submitButton = screen.getByRole("button", { name: ja.login.submit });

    await user.type(input, "test-token-12345");
    expect(submitButton).toBeEnabled();

    await user.clear(input);
    expect(submitButton).toBeDisabled();
  });
});
