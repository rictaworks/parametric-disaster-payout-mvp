// PR#57 Playwright E2E設定。
// 対象は開発サーバー相当（RAILS_ENV=test で起動するローカルRailsサーバー）のみ。
// 本番URLへの接続は行わない（global-setup.js 参照）。
const { defineConfig } = require("@playwright/test");

// この設定ファイルはPlaywright起動時（globalSetupの実行より前）に一度だけ
// 評価される。globalSetup内で設定される process.env.PR57_E2E_BASE_URL は
// このタイミングではまだ存在しないため、baseURLの組み立てにそれを使っては
// ならない（常にフォールバック値が使われてしまい、PR57_E2E_PORTでポートを
// 変更した場合に接続先がずれる）。global-setup.js と全く同じロジック
// （PR57_E2E_PORT || "34157"）でここでもポートを決定することで一致させる。
const PORT = process.env.PR57_E2E_PORT || "34157";

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: "*.e2e.spec.js",
  timeout: 30000,
  retries: 0,
  fullyParallel: false,
  workers: 1,
  globalSetup: require.resolve("./global-setup.js"),
  reporter: [ [ "list" ] ],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: "off",
  },
});
