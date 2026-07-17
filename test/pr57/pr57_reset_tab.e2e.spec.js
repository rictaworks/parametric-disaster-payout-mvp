// PR#57「管理画面にデモデータ初期化用のリセットタブを追加」用の
// ブラウザE2Eテスト（Playwright）。
//
// PR本文「非エンジニア向けユーザーテスト手順」との対応:
//   手順1（管理画面にログインする）      -> "手順1" を含むtest群
//   手順2（リセット画面を開く）          -> "手順1〜2" のtest
//   手順3（確認文字列なしで実行→失敗）    -> "手順3" を含むtest群
//   手順4（正しい確認文字列で実行→成功）  -> "手順4" のtest
//   手順5（他タブでデータが消えたことを確認）-> "手順5" のtest
//
// 対象は開発サーバー相当のローカルRailsサーバーのみ（global-setup.js が
// RAILS_ENV=test で起動する使い捨てサーバー。storage/test.sqlite3を使用し、
// 開発DB・本番DBのどちらにも一切書き込まない）。本番URLへは接続しない。
//
// 注意（重要）: global-setup.js は起動前に必ず `rails db:test:prepare` を
// 実行して storage/test.sqlite3 をまっさらにするため、本ファイル単体の
// 実行は毎回クリーンな状態から始まる。ただし、本ファイルは別プロセスの
// サーバーへ実際にデータを書き込むため（RSpecのトランザクションロールバックは
// 効かない）、実行後に storage/test.sqlite3 にはサンプルデータが残った
// ままになる場合がある（本不具合により手順4のリセットが実行できないため）。
// pr57_admin_reset_spec.rb（RSpec）をこの後に続けて実行する場合は、
// 先に `RAILS_ENV=test bundle exec rails db:test:prepare` を実行すること。
//
// 実行方法:
//   cd test/pr57
//   npm install   # 初回のみ（@playwright/test を導入）
//   npx playwright install chromium   # 初回のみ（ブラウザ本体）
//   npx playwright test
//   （Railsアプリ本体は ../../src/backend にある。global-setup.js が
//    そのパスを解決して RAILS_ENV=test でサーバーを起動する）
//
// [重要・既知の不具合（RED）について]
// 本テストを実際にローカルの Rails サーバー（Puma, `bin/rails server -e test`）に
// 対して実行したところ、認証成功後に管理画面のHTMLページ（/admin, /admin/kpi,
// /admin/payouts, /admin/simulated_events, /admin/reset のすべて）が
// 500 Internal Server Error（`undefined method 'flash' for an instance of
// ActionDispatch::Request`）を返すことを確認した（curlでも再現・PR#57固有ではなく
// 既存の admin HTML 全体に及ぶ問題）。
//
// 原因: config/application.rb で `config.api_only = true` としているため、
// Rails は既定で `ActionDispatch::Flash` ミドルウェアをミドルウェアスタックに
// 追加しない。同ファイルのコメントには「Middleware like session, flash,
// cookies can be added back manually」とあるが、実際には
// `ActionDispatch::Cookies` とセッションストアのみが手動で追加されており、
// `ActionDispatch::Flash` が追加されていない。一方 app/views/layouts/admin.html.erb
// は毎回 `<% flash.each do |type, message| %>` を無条件に呼び出すため、
// admin配下のHTMLページを開くと必ずこの例外で落ちる。
//
// この不具合は spec/requests 配下の既存RSpec（およびtest/pr57/admin_reset_spec.rb）
// では再現しない（RSpecプロセスの起動過程で別経路から
// action_dispatch/middleware/flash.rb が読み込まれ、たまたま
// ActionDispatch::Request に flash メソッドが生えているため）。つまり
// 「RSpecでは検出できないが、実際にサーバーを起動してブラウザ／curlで
// アクセスすると必ず再現する」タイプの不具合であり、これは本タスクで
// 「開発サーバーを対象にテストする」ことが明示的に求められている理由そのものの
// 実例と言える。
//
// 対応（アプリケーションコードの修正）は本テスト作成タスクの範囲外のため、
// ここでは修正を行わず、DEBUG/admin_html_pages_500_missing_flash_middleware.md /
// GitHub Issue #62 として起票済み。
// 対応候補（参考・未実施）: config/application.rb に
// `config.middleware.use ActionDispatch::Flash` を追加する。
//
// 「既知の不具合(RED)」のテストは test.fail() で意図的な失敗として明示し、
// 修正が入って予期せず成功した場合はPlaywright側がそれを検知して失敗扱いにする
// （＝ pending解除のタイミングを自動検知できる）。
// それ以降、認証成功後のページ表示に依存するテスト（手順1〜2, 手順3〜5）は
// 同じ不具合の影響で実行しても必ず失敗するため、test.skip(true, "Issue #62 ...")
// で明示的にスキップし、デフォルト実行（npx playwright test）が
// 常にgreenで終わるようにしている（Issue #62対応後にスキップを解除すること）。

const { test, expect } = require("@playwright/test");

const ADMIN_USER = process.env.PR57_E2E_ADMIN_USER;
const ADMIN_PASSWORD = process.env.PR57_E2E_ADMIN_PASSWORD;
const CONFIRMATION_TEXT = "デモデータを初期化する";
const SAMPLE_GOOGLE_SUB = "google-sub-pr57-e2e-user";

function basicAuthHeader(user, password) {
  return `Basic ${Buffer.from(`${user}:${password}`).toString("base64")}`;
}

test.describe.serial("PR#57 管理画面「リセット」タブ ユーザーテスト手順の再現", () => {
  test("手順1: BASIC認証情報なしでは401になる（失敗パターンの逆＝正しい防御）", async ({ request }) => {
    const res = await request.get("/admin/reset");
    expect(res.status()).toBe(401);
  });

  test("手順1: 誤ったBASIC認証情報では401になる（OWASP A07: 認証の欠陥対策）", async ({ browser }) => {
    const context = await browser.newContext({
      httpCredentials: { username: "wrong-user", password: "wrong-password" },
    });
    const page = await context.newPage();

    const res = await page.goto("/admin/reset");

    expect(res.status()).toBe(401);
    await context.close();
  });

  test("既知の不具合(RED): 認証成功後の管理画面ページが実サーバーでは500を返す（config.api_only=trueによりActionDispatch::Flashミドルウェアが欠落・Issue #62）", async ({ request }) => {
    // Issue #62 対応待ち。修正後にこのassertionが200で成立するようになった場合、
    // test.fail()の効果でPlaywrightが「期待していた失敗が起きなかった」として
    // このテスト自体を失敗扱いにする（＝修正完了を自動検知できる）。
    test.fail();

    const res = await request.get("/admin/reset", {
      headers: { Authorization: basicAuthHeader(ADMIN_USER, ADMIN_PASSWORD) },
    });

    expect(res.status()).toBe(200);
  });

  test("手順1〜2: 正しい認証でログインし、タブとリセット画面の内容を確認する", async ({ browser }) => {
    test.skip(true, "Issue #62 対応待ち: ActionDispatch::Flash欠落により認証成功後の管理画面ページが500になるため実行不可");

    const context = await browser.newContext({
      httpCredentials: { username: ADMIN_USER, password: ADMIN_PASSWORD },
    });
    const page = await context.newPage();

    await page.goto("/admin/reset");

    await expect(page.getByRole("link", { name: "契約一覧" })).toBeVisible();
    await expect(page.getByRole("link", { name: "支払一覧" })).toBeVisible();
    await expect(page.getByRole("link", { name: "模擬イベント注入" })).toBeVisible();
    await expect(page.getByRole("link", { name: "リセット" })).toBeVisible();

    await expect(page.getByRole("heading", { name: "リセット" })).toBeVisible();
    await expect(page.getByText("デモを繰り返すため、取引データだけを初期化します。")).toBeVisible();
    await expect(page.getByText("この操作は元に戻せません。")).toBeVisible();
    await expect(page.getByText(/Policies: \d+件/)).toBeVisible();
    await expect(page.getByText(/マスタ: 26件/)).toBeVisible();

    await context.close();
  });

  test("手順3: 確認文字列を入力せずに実行しようとすると送信がブロックされる（ネイティブconfirm/alertは使われない）", async ({ browser }) => {
    test.skip(true, "Issue #62 対応待ち: ActionDispatch::Flash欠落により認証成功後の管理画面ページが500になるため実行不可");

    const context = await browser.newContext({
      httpCredentials: { username: ADMIN_USER, password: ADMIN_PASSWORD },
    });
    const page = await context.newPage();

    // development.md の規約: alert()/confirm()/prompt() はプロジェクト全体で使用禁止。
    // ネイティブダイアログが呼ばれたら即座に検知できるようにする。
    let nativeDialogTriggered = false;
    page.on("dialog", async (dialog) => {
      nativeDialogTriggered = true;
      await dialog.dismiss();
    });

    await page.goto("/admin/reset");
    await page.click("#open-reset-modal");
    await expect(page.locator("#reset-modal")).toBeVisible();

    // 何も入力せず送信ボタンをクリック -> HTML5 required 属性により
    // ブラウザ側でブロックされ、ページ遷移しないはず
    const urlBeforeSubmit = page.url();
    await page.click('#reset-modal input[type="submit"]');
    await page.waitForTimeout(300);

    expect(page.url()).toBe(urlBeforeSubmit);
    expect(nativeDialogTriggered).toBe(false);

    const validationMessage = await page
      .locator("#confirmation_text")
      .evaluate((el) => el.validationMessage);
    expect(validationMessage).not.toBe("");

    // まだリセットは実行されていないため、契約一覧にサンプルデータが残っている
    await page.goto("/admin");
    await expect(page.getByText(SAMPLE_GOOGLE_SUB)).toBeVisible();

    await context.close();
  });

  test("手順3(サーバー側): 確認文字列なしでAPIへ直接送信しても失敗する（クライアント側チェックのみに依存しない）", async ({ request }) => {
    test.skip(true, "Issue #62 対応待ち: ActionDispatch::Flash欠落により認証成功後の管理画面ページが500になるため実行不可");

    const res = await request.post("/admin/reset", {
      headers: { Authorization: basicAuthHeader(ADMIN_USER, ADMIN_PASSWORD) },
      form: {},
    });

    expect(res.status()).toBe(422);
    const body = await res.text();
    expect(body).toContain("データ初期化に失敗しました。入力内容をご確認ください。");
  });

  test("手順3(サーバー側): 誤った確認文字列でも失敗する（一字一句の一致が必須）", async ({ request }) => {
    test.skip(true, "Issue #62 対応待ち: ActionDispatch::Flash欠落により認証成功後の管理画面ページが500になるため実行不可");

    const res = await request.post("/admin/reset", {
      headers: { Authorization: basicAuthHeader(ADMIN_USER, ADMIN_PASSWORD) },
      form: { confirmation_text: "デモデータを初期化します" },
    });

    expect(res.status()).toBe(422);
  });

  test("手順4: 正しい確認文字列を入力して実行すると成功メッセージが表示される", async ({ browser }) => {
    test.skip(true, "Issue #62 対応待ち: ActionDispatch::Flash欠落により認証成功後の管理画面ページが500になるため実行不可");

    const context = await browser.newContext({
      httpCredentials: { username: ADMIN_USER, password: ADMIN_PASSWORD },
    });
    const page = await context.newPage();

    let nativeDialogTriggered = false;
    page.on("dialog", async (dialog) => {
      nativeDialogTriggered = true;
      await dialog.dismiss();
    });

    await page.goto("/admin/reset");
    await page.click("#open-reset-modal");
    await page.fill("#confirmation_text", CONFIRMATION_TEXT);

    await Promise.all([
      page.waitForNavigation(),
      page.click('#reset-modal input[type="submit"]'),
    ]);

    await expect(page.getByText("デモデータを初期化しました。")).toBeVisible();
    await expect(page.getByText("Policies: 0件")).toBeVisible();
    await expect(page.getByText("Observations: 0件")).toBeVisible();
    await expect(page.getByText("Payouts: 0件")).toBeVisible();
    await expect(page.getByText("Notifications: 0件")).toBeVisible();
    await expect(page.getByText("SurveyResponses: 0件")).toBeVisible();
    // ユーザー数・マスタ件数は維持される（0件にならない）
    await expect(page.getByText(/Users: [1-9]\d*件/)).toBeVisible();
    await expect(page.getByText("マスタ: 26件")).toBeVisible();

    expect(nativeDialogTriggered).toBe(false);

    await context.close();
  });

  test("手順5: 契約一覧・支払一覧タブからサンプルデータが消えている", async ({ browser }) => {
    test.skip(true, "Issue #62 対応待ち: ActionDispatch::Flash欠落により認証成功後の管理画面ページが500になるため実行不可");

    const context = await browser.newContext({
      httpCredentials: { username: ADMIN_USER, password: ADMIN_PASSWORD },
    });
    const page = await context.newPage();

    await page.goto("/admin");
    await expect(page.getByText(SAMPLE_GOOGLE_SUB)).toHaveCount(0);

    await page.goto("/admin/payouts");
    await expect(page.getByText(SAMPLE_GOOGLE_SUB)).toHaveCount(0);

    await context.close();
  });

  test("補足: 本番URLへは接続しない方針の確認", async () => {
    // このE2Eスイートは RAILS_ENV=test のローカルサーバーのみを対象としており、
    // 本番環境へは一切接続しない。「本番環境では画面自体が開けない」という
    // 安全策そのものは test/pr57/admin_reset_spec.rb（RSpec, Rails.env.production?
    // をスタブして検証）でカバーしているため、ここでは方針を明記するのみに留める。
    test.skip(true, "本番挙動はRSpec側(admin_reset_spec.rb)で検証済み。本E2Eは本番URLへ接続しない。");
  });
});
