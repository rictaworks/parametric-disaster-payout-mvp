// PR #54「FR-06 マイページに契約・支払履歴・通知・アンケートを統合」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち、
//   手順6: 表示言語の切り替え（7言語）が正しく反映されることを確認する
// を、今回追加された箇所（マイページの「アンケート依頼」カード・
// 「【プロトタイプ操作】免責期間を即時経過」ボタン・「通知一覧」テーブル・
// 「支払履歴」テーブル）に絞って自動再現する。
//
// 既存の src/frontend/__tests__/mypage.test.tsx は日本語表示のみを検証しており、
// 言語切り替え（LanguageSwitcherコンポーネントを実際にクリックする）を検証する
// テストはリポジトリ内に存在しなかったため、本ファイルで新規に追加する。
//
// 検証内容:
//   (a) 既定（日本語）表示では、契約一覧・通知一覧・支払履歴・アンケート依頼が
//       日本語の見出しで表示される
//   (b) 言語切り替え（「言語」ラベルのボタン群）で「English」を選ぶと、
//       PR本文で明示されている
//       "[Prototype Action] Force waiting period elapse" を含め、
//       今回追加した見出し・ボタン文言がすべて英語に切り替わる
//   (c) 「العربية」（アラビア語）を選ぶと文言がアラビア文字になり、
//       <html dir="rtl"> になる（右から左に読む表記になることの確認）
//   (d) 失敗パターン: 言語切り替え後に一部の文言だけ日本語のまま残っていないこと
//       （今回追加した文言を洗い出して個別にアサートすることで検出する）
//
// このテストは開発サーバーには接続せず、fetch をモックしてブラウザ操作（React
// コンポーネント）の挙動のみを検証する（Jest + React Testing Library）。
// 本番サーバーには一切接続しない。
//
// 実行方法（src/frontend をカレントディレクトリとして実行。このテストファイルは
// Jest の rootDir（src/frontend）外に置かれているため、jest.config.ts の
// roots / modulePaths 設定により自動的に拾われる）:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr54" --modulePaths="<rootDir>/node_modules" -- pr54_mypage_locale_switch

import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "../../src/frontend/components/AppShell";
import MyPage from "../../src/frontend/app/mypage/page";

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

function mockFetchWithFixtures() {
  return jest.fn().mockImplementation((input: RequestInfo | URL) => {
    const url = input.toString();

    if (url === "/api/v1/policies") {
      return jsonResponse({
        policies: [
          {
            id: 321,
            plan_code: "seismic",
            station_code: "seismic_tokyo",
            payout_tier_code: "ten_thousand",
            policy_status_code: "pending",
            threshold: "0",
            waiting_until: "2099-01-01T00:00:00.000Z",
            expires_at: "2100-01-01T00:00:00.000Z",
            terminated_at: null,
          },
        ],
      });
    }

    if (url === "/api/v1/payouts") {
      return jsonResponse({
        payouts: [
          {
            id: 654,
            policy_id: 321,
            policy_plan_code: "seismic",
            policy_station_code: "seismic_tokyo",
            policy_status_code: "processing",
            policy_threshold: "0",
            payout_tier_code: "ten_thousand",
            payout_tier_amount_yen: 10_000,
            payout_status_code: "completed_simulated",
            survey_response_submitted: false,
            decided_at: "2026-07-16T01:00:00.000Z",
            created_at: "2026-07-16T01:00:00.000Z",
          },
        ],
      });
    }

    if (url === "/api/v1/notifications") {
      return jsonResponse({
        notifications: [
          {
            id: 987,
            kind: "payout_completed",
            message: "notification body",
            policy_id: 321,
            payout_id: 654,
            delivered_at: "2026-07-16T01:05:00.000Z",
            read_at: null,
            created_at: "2026-07-16T01:05:00.000Z",
          },
        ],
      });
    }

    throw new Error(`Unexpected fetch: ${url}`);
  });
}

describe("PR54 手順6: マイページの表示言語切り替え", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("(a) 既定（日本語）表示では今回追加した見出し・ボタンが日本語で表示される", async () => {
    global.fetch = mockFetchWithFixtures();

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("アンケート依頼")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "【プロトタイプ操作】免責期間を即時経過" })).toBeInTheDocument();
    expect(screen.getByText("通知一覧")).toBeInTheDocument();
    expect(screen.getByText("支払履歴")).toBeInTheDocument();
    expect(document.documentElement.dir).not.toBe("rtl");
  });

  it("(b) 「English」を選ぶと今回追加した見出し・ボタン文言がすべて英語に切り替わる", async () => {
    global.fetch = mockFetchWithFixtures();

    const user = userEvent.setup();
    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("アンケート依頼");

    await user.click(screen.getByRole("button", { name: "English" }));

    // PR本文に明記されている英語表記そのものが表示されることを確認
    expect(await screen.findByText("Survey Request")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "[Prototype Action] Force waiting period elapse" })).toBeInTheDocument();
    expect(screen.getByText("Notifications List")).toBeInTheDocument();
    expect(screen.getByText("Payout History")).toBeInTheDocument();
    expect(screen.getByText("Type")).toBeInTheDocument();
    expect(screen.getByText("Received Date")).toBeInTheDocument();

    // (d) 失敗パターンの検出: 切り替え後に日本語の見出しが残っていないこと
    expect(screen.queryByText("アンケート依頼")).not.toBeInTheDocument();
    expect(screen.queryByText("通知一覧")).not.toBeInTheDocument();
    expect(screen.queryByText("支払履歴")).not.toBeInTheDocument();
    expect(screen.queryByText("【プロトタイプ操作】免責期間を即時経過")).not.toBeInTheDocument();
  });

  it("(c) 「العربية」を選ぶとアラビア語表記になり、<html dir=\"rtl\"> になる", async () => {
    global.fetch = mockFetchWithFixtures();

    const user = userEvent.setup();
    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("アンケート依頼");

    await user.click(screen.getByRole("button", { name: "العربية" }));

    expect(await screen.findByText("طلب استطلاع")).toBeInTheDocument();
    expect(screen.getByText("سجل المدفوعات")).toBeInTheDocument();
    await waitFor(() => expect(document.documentElement.dir).toBe("rtl"));
    expect(document.documentElement.lang).toBe("ar");
  });
});
