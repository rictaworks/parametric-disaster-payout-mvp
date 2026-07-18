import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "../components/AppShell";
import MyPage from "../app/mypage/page";

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

const WAITING_UNTIL = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString();

describe("My page", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("renders the signed-in user's contracts, notifications, payout history, and survey card", async () => {
    global.fetch = jest
      .fn()
      .mockImplementation((input: RequestInfo | URL) => {
        const url = input.toString();

        if (url === "/api/v1/policies") {
          return jsonResponse({
            policies: [
              {
                id: 123,
                plan_code: "seismic",
                station_code: "seismic_tokyo",
                payout_tier_code: "ten_thousand",
                policy_status_code: "pending",
                threshold: "0",
                waiting_until: WAITING_UNTIL,
                expires_at: "2027-07-16T00:00:00.000Z",
                terminated_at: null,
              },
            ],
          });
        }

        if (url === "/api/v1/payouts") {
          return jsonResponse({
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
          });
        }

        return jsonResponse({
          notifications: [
            {
              id: 77,
              kind: "payout_completed",
              message: "支払完了（模擬）を確認しました。マイページで支払履歴をご確認ください。",
              policy_id: 123,
              payout_id: 991,
              delivered_at: "2026-07-16T01:05:00.000Z",
              read_at: null,
              created_at: "2026-07-16T01:05:00.000Z",
            },
          ],
        });
      });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText(/免責明けまで: あと/)).toBeInTheDocument();
    expect(screen.getByText("東京震度観測点")).toBeInTheDocument();
    expect(screen.getByText("支払完了（模擬）後の回答にご協力ください。")).toBeInTheDocument();
    expect(screen.getByText("支払完了（模擬）を確認しました。マイページで支払履歴をご確認ください。")).toBeInTheDocument();
    expect(screen.getByText("未回答")).toBeInTheDocument();
    expect(global.fetch).toHaveBeenCalledWith("/api/v1/policies");
    expect(global.fetch).toHaveBeenCalledWith("/api/v1/payouts");
    expect(global.fetch).toHaveBeenCalledWith("/api/v1/notifications");
  });

  it("lets the user advance the demo waiting period and cancel the contract", async () => {
    const pendingPolicy = {
      id: 123,
      plan_code: "seismic",
      station_code: "seismic_tokyo",
      payout_tier_code: "ten_thousand",
      policy_status_code: "pending",
      threshold: "0",
      waiting_until: WAITING_UNTIL,
      expires_at: "2027-07-16T00:00:00.000Z",
      terminated_at: null,
    };
    const activePolicy = {
      ...pendingPolicy,
      policy_status_code: "active",
      waiting_until: "2026-07-16T00:00:00.000Z",
    };
    const cancelledPolicy = {
      ...activePolicy,
      policy_status_code: "cancelled",
      terminated_at: "2026-07-16T02:00:00.000Z",
    };

    global.fetch = jest
      .fn()
      .mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
        const url = input.toString();

        if (url === "/api/v1/policies") {
          return jsonResponse({ policies: [pendingPolicy] });
        }

        if (url === "/api/v1/payouts") {
          return jsonResponse({ payouts: [] });
        }

        if (url === "/api/v1/notifications") {
          return jsonResponse({ notifications: [] });
        }

        if (url === "/api/v1/policies/123/force_waiting_period_elapsed" && init?.method === "PATCH") {
          return jsonResponse({ policy: activePolicy });
        }

        if (url === "/api/v1/policies/123/cancel" && init?.method === "PATCH") {
          return jsonResponse({ policy: cancelledPolicy });
        }

        throw new Error(`Unexpected fetch: ${url}`);
      });

    const user = userEvent.setup();
    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("待機中");
    await user.click(await screen.findByRole("button", { name: "【プロトタイプ操作】免責期間を即時経過" }));
    await waitFor(() => expect(screen.getByText("有効")).toBeInTheDocument());
    await user.click(screen.getByRole("button", { name: "解約" }));
    await waitFor(() => expect(screen.getByText("解約")).toBeInTheDocument());
  });

  it("submits the survey response for the completed payout", async () => {
    global.fetch = jest
      .fn()
      .mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
        const url = input.toString();

        if (url === "/api/v1/policies") {
          return jsonResponse({
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
          });
        }

        if (url === "/api/v1/payouts") {
          return jsonResponse({
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
          });
        }

        if (url === "/api/v1/notifications") {
          return jsonResponse({ notifications: [] });
        }

        if (url === "/api/v1/survey_responses" && init?.method === "POST") {
          const body = JSON.parse(init.body as string);
          expect(body.response_data.satisfaction).toBe(5);
          expect(body.response_data.feedback).toBe("今回の模擬支払体験の感想をお聞かせください。とても分かりやすい体験でした。");
          return jsonResponse({
            survey_response: {
              id: 501,
              payout_id: 991,
              response_data: body.response_data,
              created_at: "2026-07-16T02:30:00.000Z",
            },
          }, 201);
        }

        throw new Error(`Unexpected fetch: ${url}`);
      });

    const user = userEvent.setup();

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("支払完了（模擬）後の回答にご協力ください。");
    await user.type(screen.getByLabelText("回答内容"), "とても分かりやすい体験でした。");
    await user.click(screen.getByRole("button", { name: "アンケートを送信" }));

    await waitFor(() => expect(screen.getByText("回答済み")).toBeInTheDocument());
    expect(screen.queryByText("支払完了（模擬）後の回答にご協力ください。")).not.toBeInTheDocument();
  });
});
