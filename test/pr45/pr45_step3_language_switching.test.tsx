// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち
//   手順3: 7つの言語に切り替えられるか
// を自動再現するテスト。
//
// 期待される結果（PR本文より）:
//   - 日本語 / English / Français / 中文 / Русский / Español / العربية の7つのボタンを
//     それぞれクリックすると、ページ内の見出しやボタンの文字（メニュー名、注記文など）が
//     選んだ言語に切り替わる
//   - 押したボタンは他のボタンと見た目が変わり（aria-pressed等で選択中と分かる）、
//     どの言語を選んでいるかが一目でわかる
// 失敗パターン: ボタンを押しても文字が変わらない、一部の文字だけ日本語のまま残る、
//              英語表記のまま切り替わらない場合
//
// 「日本語が残っていないこと」という否定チェックだけに頼らず、各言語で実際に翻訳された
// 具体的な文言（ナビゲーションの「ホーム」相当語、常時表示バナー文言）が表示されることを
// findByText / findByRole で肯定的に確認する。
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_step3_language_switching

import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "@/components/AppShell";
import Home from "@/app/page";
import { SUPPORTED_LOCALES, type Locale } from "@/lib/i18n";
import ja from "@/locales/ja.json";
import en from "@/locales/en.json";
import fr from "@/locales/fr.json";
import zh from "@/locales/zh.json";
import ru from "@/locales/ru.json";
import es from "@/locales/es.json";
import ar from "@/locales/ar.json";

type LocaleMessages = typeof ja;

const messagesByLocale: Record<Locale, LocaleMessages> = { ja, en, fr, zh, ru, es, ar };

describe("PR45 手順3: 7つの言語に切り替えられるか", () => {
  beforeEach(() => {
    // LocaleProviderはマウント時にwindow.localStorageへ保存済みの言語設定を読み込むため、
    // 前のテストで切り替えた言語が次のテストへ持ち越されないようにリセットする。
    window.localStorage.clear();
  });

  it("SUPPORTED_LOCALES は仕様通り7言語である（日本語・英語・フランス語・中国語・ロシア語・スペイン語・アラビア語）", () => {
    expect(SUPPORTED_LOCALES).toHaveLength(7);
    expect(SUPPORTED_LOCALES).toEqual(["ja", "en", "fr", "zh", "ru", "es", "ar"]);
  });

  it("7言語すべてのボタンを順番にクリックすると、ナビゲーションと常時バナーの文言が実際にその言語へ切り替わる", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    let currentLocale: Locale = "ja";

    for (const targetLocale of SUPPORTED_LOCALES) {
      if (targetLocale === currentLocale) {
        continue;
      }

      const currentMessages = messagesByLocale[currentLocale];
      const targetLabelInCurrentLocale = currentMessages.language.options[targetLocale];

      const button = screen.getByRole("button", { name: targetLabelInCurrentLocale });
      await user.click(button);

      const targetMessages = messagesByLocale[targetLocale];

      // ナビゲーションの「ホーム」相当の文言が、選んだ言語の具体的な訳文に切り替わっていること
      expect(
        await screen.findByRole("link", { name: targetMessages.navigation.home })
      ).toBeInTheDocument();

      // 常時表示の模擬デモ注記も、選んだ言語の具体的な訳文に切り替わっていること
      expect(await screen.findByText(targetMessages.banner.notice)).toBeInTheDocument();

      // ホーム画面本文の「ログイン画面へ」相当のボタン文言も切り替わっていること
      expect(
        await screen.findByRole("link", { name: targetMessages.home.primaryAction })
      ).toBeInTheDocument();

      currentLocale = targetLocale;
    }

    // 最終的にアラビア語まで一巡していること（全7言語を実際に踏破したことの確認）
    expect(currentLocale).toBe("ar");
  });

  it("言語ボタンをクリックすると、選択中のボタンだけが aria-pressed=true になり他のボタンと見分けがつく", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    // 初期状態では日本語ボタンだけが選択中
    expect(screen.getByRole("button", { name: ja.language.options.ja })).toHaveAttribute(
      "aria-pressed",
      "true"
    );
    expect(screen.getByRole("button", { name: ja.language.options.en })).toHaveAttribute(
      "aria-pressed",
      "false"
    );

    await user.click(screen.getByRole("button", { name: ja.language.options.fr }));

    const buttons = screen.getAllByRole("button", { name: /.*/ });
    const languageButtons = buttons.filter((button) => button.closest(".language-switcher__buttons"));
    const pressedButtons = languageButtons.filter(
      (button) => button.getAttribute("aria-pressed") === "true"
    );

    // フランス語に切り替えた後、選択中のボタンは1つだけであること
    expect(pressedButtons).toHaveLength(1);
    expect(pressedButtons[0]).toHaveTextContent(fr.language.options.fr);
  });

  it("失敗パターンの回帰確認: 中国語へ切り替えても英語表記のまま残らない", async () => {
    const user = userEvent.setup();
    render(
      <AppShell>
        <Home />
      </AppShell>
    );

    await user.click(screen.getByRole("button", { name: ja.language.options.zh }));

    expect(await screen.findByRole("link", { name: zh.navigation.home })).toBeInTheDocument();
    // 英語のホームリンク文言（"Home"）が残っていないこと
    expect(screen.queryByRole("link", { name: en.navigation.home })).not.toBeInTheDocument();
  });
});
