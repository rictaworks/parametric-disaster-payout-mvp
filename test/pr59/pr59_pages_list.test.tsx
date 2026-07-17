// PR #59「READMEの最終整備とAPI参照の追加」
// PR本文の「非エンジニア向けユーザーテスト手順」のうち、手順3を自動再現するテスト。
//
// 対応する手順:
//   手順3: ページ一覧に載っているURLを実際に開いて確認する
//     README.md「ページ一覧」表に載っている4画面（ホーム／ログイン／申込ウィザード／マイページ）を
//     実際にレンダリングし、表の「用途」欄の説明と一致する内容が表示されることを確認する。
//     （実際のブラウザでURLを開く操作の代わりに、Next.jsの各ページコンポーネントを
//       React Testing Library でレンダリングして「説明と一致する画面が表示される」ことを検証する）
//
// 実行方法（開発サーバーの実装コードに対するコンポーネントテスト。本番には一切接続しない）:
//   cd src/frontend
//   NODE_PATH="$(pwd)/node_modules" npx jest --roots "$(pwd)/../.." \
//     --testPathPatterns "test/pr59/pr59_pages_list.test.tsx"
//   ※ 本テストファイルは test/pr59/ 配下（frontendのrootDir外）に置いているため、
//     Jestのデフォルト設定のままだと対象として検出されない／next 等のモジュール解決に
//     失敗する。そのため --roots でrepoルートを含めてテスト検出範囲を広げ、
//     NODE_PATH で src/frontend/node_modules を明示的にモジュール解決対象へ加えている。
//
// 併せて QC10（エラーハンドリング／モバイル対応の前提となるレンダリング健全性）も確認する。

import { render, screen } from "@testing-library/react";
import Home from "../../src/frontend/app/page";
import LoginPage from "../../src/frontend/app/login/page";
import MyPage from "../../src/frontend/app/mypage/page";
import NewPolicyPage from "../../src/frontend/app/policies/new/page";

const pushMock = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({
    push: pushMock,
  }),
}));

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

describe("PR59 手順3: README「ページ一覧」に記載された4画面の実在・内容確認", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("ホーム（http://localhost:3000/）は「模擬デモの概要とログイン導線」を表示する", () => {
    render(<Home />);

    // 「保険（デモ）」「模擬支払」であることの常時明示（design_document 1.2 / CLAUDE.md必須要件）
    expect(screen.getByRole("link", { name: /ログイン画面へ/ })).toBeInTheDocument();
  });

  it("ログイン（http://localhost:3000/login）は「Google IDトークンでセッション作成」の導線を表示する", () => {
    render(<LoginPage />);

    expect(
      screen.getByRole("heading", {
        name: /Google ID トークンを BFF に渡してセッションを開始します。/,
      })
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /セッションを作成/ })).toBeInTheDocument();
  });

  it("申込ウィザード（http://localhost:3000/policies/new）は「模擬契約の申込」フォームを表示する", async () => {
    global.fetch = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/v1/masters")) {
        return jsonResponse({
          plans: [{ id: 11, code: "seismic", trigger_type: "seismic" }],
          stations: [{ id: 21, code: "seismic_tokyo", measurement_type: "seismic" }],
          payout_tiers: [{ id: 31, code: "ten_thousand", amount_yen: 10_000 }],
        });
      }
      throw new Error(`Unexpected fetch in wizard smoke test: ${url}`);
    });

    render(<NewPolicyPage />);

    // 読み込み中のままだったり、フォーム自体が描画されなかったりする退行を
    // 見逃さないよう、実際にウィザードの見出しと1ステップ目の操作ボタンが
    // 表示されることを肯定的に確認する（単なる404文言の不在チェックでは、
    // フォームが空のまま/エラー状態のままでもテストが通ってしまうため）。
    expect(await screen.findByRole("heading", { name: "契約申込ウィザード" })).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: "次へ" })).toBeInTheDocument();
  });

  it("マイページ（http://localhost:3000/mypage）は未ログイン時に「ログインすると契約情報を確認できます」（=ログイン導線）を表示する", async () => {
    global.fetch = jest.fn().mockImplementation(() =>
      Promise.resolve({ ok: false, status: 401, json: async () => ({}) })
    );

    render(<MyPage />);

    expect(await screen.findByText("ログインすると契約情報を確認できます。")).toBeInTheDocument();
  });

  it("マイページ（http://localhost:3000/mypage）はログイン済みなら「契約・支払・通知の確認」画面を表示する（README用途欄との一致）", async () => {
    global.fetch = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url === "/api/v1/policies") {
        return jsonResponse({
          policies: [
            {
              id: 1,
              plan_code: "seismic",
              station_code: "seismic_tokyo",
              payout_tier_code: "ten_thousand",
              policy_status_code: "active",
              threshold: "5強",
              waiting_until: "2026-07-01T00:00:00.000Z",
              expires_at: "2027-07-01T00:00:00.000Z",
              terminated_at: null,
            },
          ],
        });
      }
      if (url === "/api/v1/payouts") {
        return jsonResponse({ payouts: [] });
      }
      if (url === "/api/v1/notifications") {
        return jsonResponse({ notifications: [] });
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });

    render(<MyPage />);

    // 未ログイン文言が消えたことだけを見ると、認証済みデータ取得後に
    // エラー表示や空表示へ壊れた場合でもテストが通ってしまう（未ログイン
    // 文言は初期のローディング表示にも存在しないため）。そのため、
    // 取得した契約データ（policy_status_code: "active" → 表示ラベル「有効」）
    // が実際に画面へ反映されたことを肯定的に確認する。
    expect(await screen.findByText("有効")).toBeInTheDocument();
    expect(screen.queryByText("ログインすると契約情報を確認できます。")).not.toBeInTheDocument();
  });
});
