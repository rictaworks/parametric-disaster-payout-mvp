// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順1: ホーム画面が正しく表示されるか
// を自動再現するテスト（Jest + React Testing Library）。
//
// 期待される結果（PR本文より）:
//   - ページ上部に「本サービスは保険の引受・実支払を行わない需要調査用の模擬デモです。」という
//     一文が帯（バナー）で常に表示される
//   - その下に、サービス名（パラメトリック災害保険デモ）とロゴ的なリンク、
//     ナビゲーションメニュー（ホーム／ログインを含む）、言語切り替えボタンが並んだヘッダーが表示される
//   - 本文には「ログイン画面へ」というボタンが見える
//
// 失敗パターン: 画面が真っ白、エラー表示、または模擬デモ注記の帯が表示されない場合
//
// このテストは開発サーバーには接続せず、実コンポーネントをそのままレンダリングして
// 実際に表示される文言を findByText / getByRole で肯定的に確認する。本番サーバーには一切接続しない。
//
// 実行方法（src/frontend をカレントディレクトリとして実行。このテストファイルは Jest の
// rootDir（src/frontend）外に置かれているため、--roots と --modulePaths を明示的に指定する）:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step1_home_page

import { render, screen } from "@testing-library/react";
import { AppShell } from "@/components/AppShell";
import Home from "@/app/page";
import ja from "@/locales/ja.json";

describe("PR45 手順1: ホーム画面が正しく表示されるか", () => {
  it("模擬デモ注記のバナーが帯として常時表示される", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    const banner = screen.getByRole("note");
    expect(banner).toHaveTextContent(ja.banner.notice);
    expect(banner).toHaveTextContent(
      "本サービスは保険の引受・実支払を行わない需要調査用の模擬デモです。"
    );
  });

  it("サービス名とロゴ的なリンクを含むヘッダーが表示される", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    const brandLink = screen.getByRole("link", { name: ja.app.title });
    expect(brandLink).toBeInTheDocument();
    expect(brandLink).toHaveAttribute("href", "/");
    expect(screen.getByText(ja.app.title)).toBeInTheDocument();
  });

  it("「ホーム」「ログイン」を含むナビゲーションメニューが表示される", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    const nav = screen.getByRole("navigation", { name: ja.navigation.label });
    expect(nav).toBeInTheDocument();
    expect(screen.getByRole("link", { name: ja.navigation.home })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: ja.navigation.login })).toHaveAttribute(
      "href",
      "/login"
    );
  });

  it("言語切り替えボタンが表示される", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    const languageGroup = screen.getByRole("group", { name: ja.language.label });
    expect(languageGroup).toBeInTheDocument();
    // 7言語すべてのボタンが存在すること
    for (const label of Object.values(ja.language.options)) {
      expect(screen.getByRole("button", { name: label })).toBeInTheDocument();
    }
  });

  it("本文に「ログイン画面へ」ボタン（リンク）が表示される", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    const primaryAction = screen.getByRole("link", { name: ja.home.primaryAction });
    expect(primaryAction).toBeInTheDocument();
    expect(primaryAction).toHaveAttribute("href", "/login");
    expect(primaryAction).toHaveTextContent("ログイン画面へ");
  });

  it("失敗パターンの回帰確認: エラーメッセージ文字列（Error / 500 / 404）が表示されていない", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    const body = document.body.textContent ?? "";
    expect(body).not.toMatch(/\b(Error|500|404)\b/);
  });
});
