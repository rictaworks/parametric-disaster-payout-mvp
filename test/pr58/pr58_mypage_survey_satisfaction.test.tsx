// PR #58「管理画面にKPIタブと集計APIを追加」
//
// PR本文に書かれた「非エンジニア向けユーザーテスト手順」のうち、フロントエンド（マイページ）に
// 関わる部分を自動再現するテスト。
//
// 対応する手順:
//   手順3: マイページのアンケートフォームで「満足度」を選べることを確認する
//          -> 以下の it ブロックで、
//             (a) 「満足度（1: 不満 〜 5: 満足）」の見出しと1〜5のラジオボタンが表示されること
//             (b) 初期状態では「5」が選択されていること
//             (c) 「3」をクリックすると「3」だけが選択され「5」の選択が外れること（複数同時選択にならない）
//             (d) 「アンケートを送信」を押すと選択した満足度の値でPOSTされ、
//                 成功時に「アンケートを保存しました。（支払ID: 〇〇）」が表示されること
//             (e) 失敗パターン: サーバがエラーを返した場合は
//                 「アンケートの送信に失敗しました。」が表示されること
//          をそれぞれ検証する。
//
// このテストは開発サーバーには接続せず、fetch をモックしてブラウザ操作（React コンポーネント）の
// 挙動のみを検証する（Jest + React Testing Library）。本番サーバーには一切接続しない。
//
// 実行方法（src/frontend をカレントディレクトリとして実行。このテストファイルは Jest の
// rootDir（src/frontend）外に置かれているため、--roots と --modulePaths を明示的に指定する）:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr58" --modulePaths="<rootDir>/node_modules" -- pr58_mypage_survey_satisfaction

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

const readyPayoutFixtures = {
  policies: [
    {
      id: 123,
      plan_code: "seismic",
      station_code: "seismic_tokyo",
      payout_tier_code: "ten_thousand",
      policy_status_code: "active",
      threshold: "0",
      waiting_until: "2026-07-16T00:00:00.000Z",
      expires_at: "2027-07-16T00:00:00.000Z",
      terminated_at: null,
    },
  ],
  payouts: [
    {
      id: 991,
      policy_id: 123,
      policy_plan_code: "seismic",
      policy_station_code: "seismic_tokyo",
      policy_status_code: "active",
      policy_threshold: "0",
      payout_tier_code: "ten_thousand",
      payout_tier_amount_yen: 10_000,
      payout_status_code: "completed_simulated",
      survey_response_submitted: false,
      decided_at: "2026-07-16T01:00:00.000Z",
      created_at: "2026-07-16T01:00:00.000Z",
    },
  ],
  notifications: [],
};

function mockFetchForReadySurvey(onSurveyPost: (body: { response_data: { satisfaction: number; feedback: string } }) => Promise<unknown>) {
  return jest.fn().mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
    const url = input.toString();

    if (url === "/api/v1/policies") {
      return jsonResponse({ policies: readyPayoutFixtures.policies });
    }
    if (url === "/api/v1/payouts") {
      return jsonResponse({ payouts: readyPayoutFixtures.payouts });
    }
    if (url === "/api/v1/notifications") {
      return jsonResponse({ notifications: readyPayoutFixtures.notifications });
    }
    if (url === "/api/v1/survey_responses" && init?.method === "POST") {
      const body = JSON.parse(init.body as string);
      return onSurveyPost(body);
    }

    throw new Error(`Unexpected fetch: ${url}`);
  });
}

describe("PR58 手順3: マイページのアンケートフォームの満足度ラジオボタン", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("(a)(b) 「満足度（1: 不満 〜 5: 満足）」の見出しと1〜5のラジオボタンが表示され、初期状態では「5」が選択されている", async () => {
    global.fetch = mockFetchForReadySurvey(() => jsonResponse({ survey_response: { id: 1, payout_id: 991 } }, 201));

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("満足度（1: 不満 〜 5: 満足）")).toBeInTheDocument();

    const radios = [1, 2, 3, 4, 5].map((value) => screen.getByRole("radio", { name: String(value) }));
    expect(radios).toHaveLength(5);

    const checkedValues = radios.filter((radio) => (radio as HTMLInputElement).checked).map((radio) => (radio as HTMLInputElement).value);
    expect(checkedValues).toEqual(["5"]);
  });

  it("(c) 「3」をクリックすると「3」だけが選択され、他は選択が外れる（単一選択であること）", async () => {
    global.fetch = mockFetchForReadySurvey(() => jsonResponse({ survey_response: { id: 1, payout_id: 991 } }, 201));

    const user = userEvent.setup();
    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("満足度（1: 不満 〜 5: 満足）");

    const radioThree = screen.getByRole("radio", { name: "3" }) as HTMLInputElement;
    const radioFive = screen.getByRole("radio", { name: "5" }) as HTMLInputElement;

    expect(radioFive.checked).toBe(true);
    expect(radioThree.checked).toBe(false);

    await user.click(radioThree);

    expect(radioThree.checked).toBe(true);
    expect(radioFive.checked).toBe(false);

    const allRadios = [1, 2, 3, 4, 5].map((value) => screen.getByRole("radio", { name: String(value) }) as HTMLInputElement);
    const checkedCount = allRadios.filter((radio) => radio.checked).length;
    expect(checkedCount).toBe(1);
  });

  it("(d) 選択した満足度の値でPOSTされ、成功メッセージ「アンケートを保存しました。（支払ID: 991）」が表示される", async () => {
    let receivedSatisfaction: number | null = null;

    global.fetch = mockFetchForReadySurvey((body) => {
      receivedSatisfaction = body.response_data.satisfaction;
      return jsonResponse(
        {
          survey_response: {
            id: 501,
            payout_id: 991,
            response_data: body.response_data,
            created_at: "2026-07-16T02:30:00.000Z",
          },
        },
        201
      );
    });

    const user = userEvent.setup();
    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("満足度（1: 不満 〜 5: 満足）");
    await user.click(screen.getByRole("radio", { name: "3" }));
    await user.click(screen.getByRole("button", { name: "アンケートを送信" }));

    await waitFor(() => expect(screen.getByText("アンケートを保存しました。（支払ID: 991）")).toBeInTheDocument());
    expect(receivedSatisfaction).toBe(3);
    expect(screen.queryByText("満足度（1: 不満 〜 5: 満足）")).not.toBeInTheDocument();
  });

  it("(e) 失敗パターン: サーバがエラーを返した場合は「アンケートの送信に失敗しました。」が表示される", async () => {
    global.fetch = mockFetchForReadySurvey(() => jsonResponse({ error: ["満足度が不正です"] }, 422));

    const user = userEvent.setup();
    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("満足度（1: 不満 〜 5: 満足）");
    await user.click(screen.getByRole("button", { name: "アンケートを送信" }));

    await waitFor(() => expect(screen.getByText("アンケートの送信に失敗しました。")).toBeInTheDocument());
    // 失敗時はカードが消えず、再送信できる状態が保たれる（QC10: エラー時も操作不能にならないこと）
    expect(screen.getByText("満足度（1: 不満 〜 5: 満足）")).toBeInTheDocument();
  });
});
