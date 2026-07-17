// PR#57 Playwright E2E用のグローバルセットアップ。
//
// - 対象は「開発サーバー」相当のRailsサーバーのみ（本番には一切接続しない）。
//   具体的には RAILS_ENV=test（storage/test.sqlite3）でサーバーを起動する。
//   RAILS_ENV=development ではなく test を使う理由:
//     Admin::ResetController は Rails.env.production? のみを見て実行可否を
//     判定するため、development でも test でも挙動は同一である。一方で
//     development 用DB（storage/development.sqlite3）は他の作業・確認で
//     共有される可能性があるため、この破壊的テスト（実際にデータを削除する）
//     専用に隔離された test 用DBを使うことで、開発DBを誤って消さないようにする。
// - サーバー起動前に schema 準備 + マスタ26件 + サンプル契約1件を投入する。
// - グローバルティアダウン（サーバープロセスの終了）はこの関数が返す関数で行う
//   （Playwright の仕様：globalSetup が関数を return すると自動的に
//   globalTeardown として実行される）。
//
// [安全策・重要]
// process.env をそのまま子プロセスへ引き継ぐと、開発者のシェルに
// DATABASE_URL（本来は production 用）が設定されている場合、Rails は
// database.yml の test セクションの記述に関わらず DATABASE_URL を優先して
// 接続先を決定してしまう（Railsの既知の挙動）。その状態で破壊的な
// db:test:prepare を実行すると、共有DB・本番相当DBを巻き込みかねない。
// そのため (1) 子プロセス環境から DATABASE_URL を明示的に除去し、
// (2) 破壊的処理の直前に実際の接続先がローカルの使い捨てSQLite test DBで
// あることを検証してから db:test:prepare を実行する。

const { spawn, execFileSync } = require("node:child_process");
const path = require("node:path");
const http = require("node:http");
const net = require("node:net");

// このファイルはリポジトリ直下の test/pr57/ に置かれている（tester運用ルール
// 「保存先は test/pr<PR番号>/ とする」に合わせたもの）。Railsアプリ本体は
// src/backend にあるため、そこへ絶対パスで解決する。
const BACKEND_ROOT = path.resolve(__dirname, "..", "..", "src", "backend");
const SEED_SCRIPT = path.resolve(__dirname, "seed_sample_data.rb");
const PORT = process.env.PR57_E2E_PORT || "34157";
const HOST = "127.0.0.1";
const ADMIN_USER = "pr57_e2e_admin";
const ADMIN_PASSWORD = "pr57_e2e_password";
const EXPECTED_TEST_DB_PATH = path.resolve(BACKEND_ROOT, "storage", "test.sqlite3");

function buildChildEnv() {
  const env = { ...process.env, RAILS_ENV: "test", ADMIN_BASIC_USER: ADMIN_USER, ADMIN_BASIC_PASSWORD: ADMIN_PASSWORD };

  // DATABASE_URL 等、環境変数によるDB接続先の上書きを許さない
  // （db.yml の test セクションが常に唯一の真実になるようにする）。
  delete env.DATABASE_URL;

  return env;
}

function assertUsingLocalSqliteTestDb(env) {
  const output = execFileSync(
    "bundle",
    [
      "exec", "rails", "runner",
      "config = ActiveRecord::Base.configurations.configs_for(env_name: 'test').first; " +
        "puts [config.adapter, config.database].join('|')",
    ],
    { cwd: BACKEND_ROOT, env, encoding: "utf8" }
  ).trim();

  const [ adapter, database ] = output.split("|");
  const actualPath = path.resolve(BACKEND_ROOT, database);

  if (adapter !== "sqlite3" || actualPath !== EXPECTED_TEST_DB_PATH) {
    throw new Error(
      "安全チェック失敗: db:test:prepare の接続先がローカルの使い捨てSQLite test DB " +
        `(${EXPECTED_TEST_DB_PATH}) ではありません（adapter=${adapter}, database=${actualPath}）。` +
        "DATABASE_URL 等の環境変数がRailsの接続先を上書きしていないか確認してください。破壊的処理は中止します。"
    );
  }
}

function assertPortIsFree(port, host) {
  return new Promise((resolve, reject) => {
    const tester = net.createServer();
    tester.once("error", (err) => {
      tester.close();
      reject(new Error(`ポート ${port} は既に使用中のため起動できません（${err.message}）。無関係なサービスを誤って` +
        "テストしないよう、E2E実行前に空きポートを用意するか PR57_E2E_PORT で別ポートを指定してください。"));
    });
    tester.once("listening", () => {
      tester.close(() => resolve());
    });
    tester.listen(port, host);
  });
}

function waitForServer(child, url, timeoutMs) {
  const deadline = Date.now() + timeoutMs;

  return new Promise((resolve, reject) => {
    let settled = false;

    const onChildDown = (detail) => {
      if (settled) return;
      settled = true;
      reject(new Error(`Rails子プロセスが起動完了前に終了しました: ${detail}`));
    };

    child.once("error", (err) => onChildDown(err.message));
    child.once("exit", (code, signal) => onChildDown(`code=${code} signal=${signal}`));

    const attempt = () => {
      if (settled) return;

      const req = http.get(url, (res) => {
        res.resume();
        if (settled) return;
        settled = true;
        resolve();
      });

      req.on("error", () => {
        if (settled) return;
        if (Date.now() > deadline) {
          settled = true;
          reject(new Error(`Rails server did not become ready at ${url} within ${timeoutMs}ms`));
          return;
        }
        setTimeout(attempt, 300);
      });
    };

    attempt();
  });
}

function killAndWait(child, timeoutMs = 5000) {
  return new Promise((resolve) => {
    if (!child || child.exitCode !== null || child.signalCode !== null) {
      resolve();
      return;
    }

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
    }, timeoutMs);

    child.once("exit", () => {
      clearTimeout(timer);
      resolve();
    });

    child.kill("SIGTERM");
  });
}

module.exports = async () => {
  // 本番環境を対象にしないことをここでも二重に強制する。
  if (process.env.RAILS_ENV === "production") {
    throw new Error("PR#57 E2E must never run against RAILS_ENV=production");
  }

  const env = buildChildEnv();

  // 0. ポートが空いていることを確認してから起動する
  //    （既に何らかのサービスが同ポートで稼働している場合、無関係な
  //    サービスへ認証・リセット要求を送ってしまうことを防ぐ）。
  await assertPortIsFree(PORT, HOST);

  // 1. 破壊的処理（db:test:prepare）の前に、接続先が想定のローカル
  //    SQLite test DBであることを検証する。
  assertUsingLocalSqliteTestDb(env);

  // 2. スキーマ準備（storage/test.sqlite3 のみを対象）
  execFileSync("bundle", [ "exec", "rails", "db:test:prepare" ], {
    cwd: BACKEND_ROOT,
    env,
    stdio: "inherit",
  });

  // 3. マスタ26件 + PR#57手順5用のサンプル契約1件を投入（冪等）
  execFileSync("bundle", [ "exec", "rails", "runner", SEED_SCRIPT ], {
    cwd: BACKEND_ROOT,
    env,
    stdio: "inherit",
  });

  // 4. 開発サーバー相当（RAILS_ENV=test）をローカルポートで起動
  const child = spawn(
    "bundle",
    [ "exec", "rails", "server", "-e", "test", "-p", PORT, "-b", HOST ],
    {
      cwd: BACKEND_ROOT,
      env,
      stdio: "inherit",
    }
  );

  try {
    await waitForServer(child, `http://${HOST}:${PORT}/up`, 60000);
  } catch (err) {
    // ヘルスチェック失敗・タイムアウト時にプロセスを残留させない
    // （このtry/catchを通らないと globalTeardown が一切登録されず、
    // spawn済みのRailsプロセスがゾンビ化してしまう）。
    await killAndWait(child);
    throw err;
  }

  // baseURL は playwright.config.js が起動前に PR57_E2E_PORT から直接
  // 組み立てるため、ここでは PR57_E2E_BASE_URL を設定しない（設定しても
  // config評価タイミングの都合で参照されず、混乱の元になるため）。
  process.env.PR57_E2E_ADMIN_USER = ADMIN_USER;
  process.env.PR57_E2E_ADMIN_PASSWORD = ADMIN_PASSWORD;

  return async () => {
    await killAndWait(child);
  };
};
