// PR #64「Jestがtest/pr**配下のテストも実行できるようにする」用の自動テスト。
//
// このPR自体はテストコードを1件も追加しておらず、`src/frontend/jest.config.ts` の
// 設定変更（roots / testMatch / modulePaths）のみのPRである。したがって本ファイルは
// 「機能」ではなく「Jestのテストランナー設定が意図通りに機能しているか」を検証する。
//
// PR本文「非エンジニア向けユーザーテスト手順」との対応:
//   手順1（ターミナルを開く）                          -> 前提。テスト内では省略
//   手順2（cd src/frontend && npm install && npm test） -> "手順1〜3: npm test ..." のtest
//   手順3（Test Suites/Tests の表示でfailedが0件）       -> 同上のtestでexit code・summary文字列を確認
//   手順4（failedが0件でない場合は問題の可能性）          -> 同上のtestが失敗＝redとして検知される
//
// PR本文に明記された「変更内容」3点をそれぞれ検証する:
//   1. roots にリポジトリ直下の test/ が含まれる
//      -> "設定確認1: roots にリポジトリ直下の test/ が含まれる"
//   2. testMatch が .test.ts(x) 命名のみを対象にし、test/pr57 の *.e2e.spec.js を
//      誤って拾わない
//      -> "設定確認2: testMatch が .test.ts(x) のみを対象にする" と
//         "手順3(回帰確認): --listTests に test/pr57 の *.e2e.spec.js が含まれない"
//   3. modulePaths で next/react 等のモジュール解決先を明示（node_modules起点の
//      解決に成功すること自体は "手順1〜3" のnpm testが green で完了することで
//      間接的に確認される。設定値そのものの存在確認は
//      "設定確認3: modulePaths が src/frontend/node_modules を指す" で行う）
//
// テスト対象は開発用のローカルコマンド（npx jest --listTests / npm test）の実行結果のみ。
// 起動する子プロセスはJest（Node.js製のテストランナー）自体であり、Railsサーバー・
// DB・ネットワークのいずれにも一切接続しない（本番はもちろん開発サーバーにも接続しない、
// フロントエンドのビルド設定を検証するテストであるため対象外）。
//
// このPRはビルド設定のみのdiffであり、QC10/OWASP10で直接該当する項目はほぼ無い。
// 強いて関連するのは以下の2点のみで、"QC10/OWASP10 該当観点" セクションで確認する:
//   QC10 (エラーハンドリング): 対象外テストファイル（*.e2e.spec.js）を誤検出した場合に
//     不可解な失敗としてCIが赤くなる、という「エラーの分かりにくさ」を防ぐ設定であるため
//     回帰確認テストを設けている
//   OWASP A08 (ソフトウェア／データの整合性): jest.config.ts というビルド・テスト設定の
//     改ざん・意図しない変更を検知する回帰テストという位置づけ
//
// 実行方法（本ファイルはJestではなくNode.js組み込みのテストランナーで書かれている。
// pr58/pr59のようにJest自身で書くと「Jest設定の検証をJestで行う」自己参照になり、
// 対象のjest.config.tsが壊れている場合にテストランナー自体が起動できず検証にならない
// ため、意図的に依存のないプレーンなNode.jsスクリプトとして作成した）:
//   node --test test/pr64/pr64_jest_config_roots_test.js
// または
//   node --test test/pr64
//
// 実行結果メモ（作成時点）:
//   全項目 green。npx jest --listTests に test/pr58, test/pr59 のテストファイルが
//   含まれ、test/pr57 の *.e2e.spec.js は含まれないことを確認済み。
//   npm test -- --ci --passWithNoTests は 21 suites / 117 tests / 0 failures で完了。
//   （PR本文記載の「11 suites / 44 tests」から件数が増えているのは、PR #64 以降に
//   他PR分のテストが追加されたため。PR本文も「数字は完全一致でなくてよいが failed が
//   0 であること」と明記しているため、件数一致ではなく failed=0 を検証する）

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const FRONTEND_DIR = path.join(REPO_ROOT, "src", "frontend");
const JEST_CONFIG_PATH = path.join(FRONTEND_DIR, "jest.config.ts");

const EXPECTED_ROOTS_TEST_ENTRY = "<rootDir>/../../test";
const EXPECTED_MODULE_PATHS_ENTRY = "<rootDir>/node_modules";

const EXPECTED_DETECTED_TEST_FILES = [
  path.join(REPO_ROOT, "test", "pr58", "pr58_mypage_survey_satisfaction.test.tsx"),
  path.join(REPO_ROOT, "test", "pr59", "pr59_pages_list.test.tsx"),
];
const EXPECTED_UNDETECTED_SPEC_FILE = path.join(
  REPO_ROOT,
  "test",
  "pr57",
  "pr57_reset_tab.e2e.spec.js"
);

const SPAWN_TIMEOUT_MS = 180000;

function readJestConfigSource() {
  assert.ok(
    fs.existsSync(JEST_CONFIG_PATH),
    `jest.config.ts が見つかりません: ${JEST_CONFIG_PATH}`
  );
  return fs.readFileSync(JEST_CONFIG_PATH, "utf8");
}

function extractArrayLiteral(source, key) {
  // "roots: [...]" のような単純なオブジェクトリテラルの配列部分だけを取り出す。
  // jest.config.ts はプロジェクト内で唯一のシンプルな設定ファイルであり、
  // 複雑な式は使われていない前提（複雑化した場合はTypeScriptとしてimportして
  // 型安全に検証する方式へ切り替えるべき）。
  const regex = new RegExp(`${key}:\\s*\\[([\\s\\S]*?)\\]`);
  const matched = source.match(regex);
  return matched ? matched[1] : null;
}

function safeChildEnv() {
  // 子プロセスとして起動するのはJest（フロントエンドのローカルテストランナー）のみで
  // あり、DB・Railsサーバーへは一切接続しない。ただし tester-ci-wiring-convention の
  // 教訓（別プロセスへ本番向けDATABASE_URLを引き継いでしまう事故の再発防止）を踏襲し、
  // 念のため子プロセスの環境からDATABASE_URLを取り除いておく。
  const env = { ...process.env };
  delete env.DATABASE_URL;
  return env;
}

function runJestListTests() {
  const npxCommand = process.platform === "win32" ? "npx.cmd" : "npx";
  const result = spawnSync(npxCommand, ["jest", "--listTests"], {
    cwd: FRONTEND_DIR,
    env: safeChildEnv(),
    encoding: "utf8",
    timeout: SPAWN_TIMEOUT_MS,
  });

  assert.equal(
    result.status,
    0,
    `npx jest --listTests がexit code 0で終了しませんでした（status=${result.status}）。` +
      `stderr: ${result.stderr}`
  );

  return result.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

test("設定確認1: jest.config.ts の roots にリポジトリ直下の test/ が含まれる", () => {
  const source = readJestConfigSource();
  const rootsLiteral = extractArrayLiteral(source, "roots");

  assert.ok(rootsLiteral, "jest.config.ts に roots 設定が見つかりません");
  assert.ok(
    rootsLiteral.includes(EXPECTED_ROOTS_TEST_ENTRY),
    `roots に "${EXPECTED_ROOTS_TEST_ENTRY}" が含まれていません: ${rootsLiteral}`
  );
});

test("設定確認2: testMatch が .test.ts(x) 命名のみを対象にし、*.spec.js 命名は対象に含まない", () => {
  const source = readJestConfigSource();
  const testMatchLiteral = extractArrayLiteral(source, "testMatch");

  assert.ok(testMatchLiteral, "jest.config.ts に testMatch 設定が見つかりません");
  assert.ok(
    /test/.test(testMatchLiteral),
    `testMatch に "test" 命名を対象にするパターンが見当たりません: ${testMatchLiteral}`
  );
  assert.ok(
    !/\.spec\./.test(testMatchLiteral),
    `testMatch に "*.spec.*" 命名を許すパターンが含まれています` +
      `（test/pr57のPlaywright用ファイルを誤検出する可能性）: ${testMatchLiteral}`
  );
});

test("設定確認3: modulePaths が src/frontend/node_modules（rootDir配下）を指している", () => {
  const source = readJestConfigSource();
  const modulePathsLiteral = extractArrayLiteral(source, "modulePaths");

  assert.ok(modulePathsLiteral, "jest.config.ts に modulePaths 設定が見つかりません");
  assert.ok(
    modulePathsLiteral.includes(EXPECTED_MODULE_PATHS_ENTRY),
    `modulePaths に "${EXPECTED_MODULE_PATHS_ENTRY}" が含まれていません: ${modulePathsLiteral}`
  );
});

test("手順3: npx jest --listTests に test/pr58, test/pr59 のJestテストファイルが検出される", () => {
  const detectedFiles = runJestListTests();

  for (const expectedFile of EXPECTED_DETECTED_TEST_FILES) {
    assert.ok(
      detectedFiles.includes(expectedFile),
      `${expectedFile} が --listTests の検出結果に含まれていません。` +
        `検出結果: ${JSON.stringify(detectedFiles, null, 2)}`
    );
  }
});

test("手順3(回帰確認): --listTests に test/pr57 のPlaywright用 *.e2e.spec.js は含まれない", () => {
  const detectedFiles = runJestListTests();

  assert.ok(
    !detectedFiles.includes(EXPECTED_UNDETECTED_SPEC_FILE),
    `${EXPECTED_UNDETECTED_SPEC_FILE} が誤って --listTests の検出結果に含まれています` +
      "（testMatchがspec命名まで拾ってしまう回帰）"
  );
});

test("手順1〜3: npm test -- --ci --passWithNoTests がexit code 0で完了し、failedが0件である", () => {
  const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
  const result = spawnSync(npmCommand, ["test", "--", "--ci", "--passWithNoTests"], {
    cwd: FRONTEND_DIR,
    env: safeChildEnv(),
    encoding: "utf8",
    timeout: SPAWN_TIMEOUT_MS,
  });

  // Jestのサマリー（"Test Suites:" / "Tests:" 等）はstderrに出力される。
  const combinedOutput = `${result.stdout}\n${result.stderr}`;

  assert.equal(
    result.status,
    0,
    `npm test -- --ci --passWithNoTests がexit code 0で終了しませんでした` +
      `（status=${result.status}）。出力:\n${combinedOutput}`
  );

  const suitesMatch = combinedOutput.match(/Test Suites:\s*(.+)/);
  const testsMatch = combinedOutput.match(/Tests:\s*(.+)/);

  assert.ok(suitesMatch, `出力に "Test Suites:" の表示が見つかりません:\n${combinedOutput}`);
  assert.ok(testsMatch, `出力に "Tests:" の表示が見つかりません:\n${combinedOutput}`);

  assert.ok(
    !/\d+\s+failed/.test(suitesMatch[1]),
    `Test Suites に failed が含まれています: ${suitesMatch[1]}`
  );
  assert.ok(
    !/\d+\s+failed/.test(testsMatch[1]),
    `Tests に failed が含まれています: ${testsMatch[1]}`
  );
});

test("QC10/OWASP10 該当観点: このテスト自身が子プロセスとしてRailsサーバー/DBへ接続しない（Jestのみを起動する）ことの明示", () => {
  // このPRはフロントエンドのビルド・テスト設定のみのdiffであり、DBアクセスや
  // ネットワーク越しの外部接続は本来発生しない。上記のtestで起動している子プロセスが
  // すべて "npx jest ..." / "npm test ..."（= Jest自体）であることをコマンド文字列
  // レベルで再確認し、将来的な変更でうっかりRailsサーバーやDB接続コマンドが
  // 混入する回帰を防ぐ。
  const source = fs.readFileSync(__filename, "utf8");
  const spawnCalls = source.match(/spawnSync\(\s*[^,]+,\s*\[[^\]]*\]/g) || [];

  assert.ok(spawnCalls.length > 0, "spawnSync呼び出しが見つかりません");
  for (const call of spawnCalls) {
    assert.ok(
      /jest|npm/.test(call),
      `想定外のコマンドを子プロセスとして起動しています: ${call}`
    );
    assert.ok(
      !/rails|rspec|psql|mysql|sqlite3\b/i.test(call),
      `DB/Railsサーバーに接続しうるコマンドが含まれています: ${call}`
    );
  }
});
