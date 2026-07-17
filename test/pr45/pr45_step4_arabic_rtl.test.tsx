// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順4: アラビア語を選んだときに右から左書き（RTL）になるか
// を自動再現するテスト。
//
// 期待される結果（PR本文より）:
//   - 「العربية」（アラビア語）を選ぶと、文字がアラビア語に変わると同時に、
//     画面全体のレイアウトが右から左方向（RTL）に反転する
//   - 確認が終わったら日本語に戻すと、レイアウトは左から右（LTR）に戻る
// 失敗パターン: 文字はアラビア語になるが、レイアウトが左から右のままで変わらない場合
//
// このPRのセキュリティレビュー対応（PR本文の対応事項5）でも
// 「アラビア語を選んだときに、画面が正しく右から左書き（RTL）で表示されるように修正した」
// と明記されているため、実際に document.documentElement.dir が切り替わることまで確認する。
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step4_arabic_rtl

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "@/components/AppShell";
import Home from "@/app/page";
import { SUPPORTED_LOCALES, getTextDirection, type Locale } from "@/lib/i18n";
import ja from "@/locales/ja.json";
import ar from "@/locales/ar.json";

describe("PR45 手順4: アラビア語を選んだときに右から左書き（RTL）になるか", () => {
  beforeEach(() => {
    // LocaleProviderはマウント時にwindow.localStorageへ保存済みの言語設定を読み込むため、
    // 前のテストで切り替えた言語が次のテストへ持ち越されないようにリセットする。
    window.localStorage.clear();
    document.documentElement.dir = "ltr";
    document.documentElement.lang = "ja";
  });

  it("初期状態（日本語）では画面は左から右（LTR）である", () => {
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    expect(document.documentElement.dir).toBe("ltr");
    expect(document.documentElement.lang).toBe("ja");
  });

  it("アラビア語ボタンを押すと、文字がアラビア語に変わると同時に画面全体がRTLへ反転する", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    await user.click(screen.getByRole("button", { name: ja.language.options.ar }));

    // 文字がアラビア語の具体的な訳文に変わっていること
    expect(await screen.findByText(ar.banner.notice)).toBeInTheDocument();
    expect(await screen.findByRole("link", { name: ar.navigation.home })).toBeInTheDocument();

    // レイアウト全体がRTLに反転していること（html要素のdir/lang属性で判定）
    expect(document.documentElement.dir).toBe("rtl");
    expect(document.documentElement.lang).toBe("ar");
  });

  it("アラビア語から日本語に戻すと、レイアウトは左から右（LTR）に戻る", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    await user.click(screen.getByRole("button", { name: ja.language.options.ar }));
    expect(document.documentElement.dir).toBe("rtl");

    // アラビア語表示中の「日本語」ボタン（ar.language.options.ja）を押して戻す
    await user.click(screen.getByRole("button", { name: ar.language.options.ja }));

    expect(await screen.findByText(ja.banner.notice)).toBeInTheDocument();
    expect(document.documentElement.dir).toBe("ltr");
    expect(document.documentElement.lang).toBe("ja");
  });

  it("アラビア語以外の6言語はすべてLTRのままであること（getTextDirectionの網羅確認）", () => {
    expect(getTextDirection("ar")).toBe("rtl");

    for (const locale of SUPPORTED_LOCALES.filter((value): value is Locale => value !== "ar")) {
      expect(getTextDirection(locale)).toBe("ltr");
    }
  });
});
