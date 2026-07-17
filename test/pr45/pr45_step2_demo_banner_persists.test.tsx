// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順2: 常時表示のデモ注記がどの画面でも消えないか
// を自動再現するテスト。
//
// 期待される結果（PR本文より）:
//   - ホーム画面からログイン画面へ移動しても、手順1で見たのと同じ
//     「模擬デモです」という注記の帯がログイン画面でも変わらず表示され続ける
// 失敗パターン: ログイン画面に移動した際にこの注記が消えている、または表示されない場合
//
// 本テストではNext.jsのルーティングそのものは対象とせず（BFFログイン導線PRの範囲外）、
// ホーム画面・ログイン画面それぞれをAppShellでラップしてレンダリングし、
// 同一のバナー文言が両画面で表示され続けることを確認する。
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step2_demo_banner_persists

import { render, screen } from "@testing-library/react";
import { AppShell } from "@/components/AppShell";
import Home from "@/app/page";
import LoginPage from "@/app/login/page";
import ja from "@/locales/ja.json";

describe("PR45 手順2: 常時表示のデモ注記がどの画面でも消えないか", () => {
  it("ホーム画面で模擬デモ注記が表示される", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    expect(screen.getByRole("note")).toHaveTextContent(ja.banner.notice);
  });

  it("ログイン画面でも同じ模擬デモ注記が変わらず表示される", () => {
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    expect(screen.getByRole("note")).toHaveTextContent(ja.banner.notice);
  });

  it("失敗パターンの回帰確認: ログイン画面のページ固有コンテンツが表示されていても注記は1つだけ消えずに残る", () => {
    render(
      <AppShell>
        <LoginPage />
      </AppShell>
    );

    // ページ固有のログインフォーム見出しが表示されていることを確認しつつ
    expect(
      screen.getByRole("heading", { name: ja.login.title })
    ).toBeInTheDocument();
    // バナーはページの中身に関わらず1つだけ存在し続ける（消えていない）
    expect(screen.getAllByRole("note")).toHaveLength(1);
    expect(screen.getByRole("note")).toHaveTextContent(
      "本サービスは保険の引受・実支払を行わない需要調査用の模擬デモです。"
    );
  });
});
