import { render, screen } from "@testing-library/react";
import { AppShell } from "../components/AppShell";
import MyPage from "../app/mypage/page";

describe("My page", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("renders the signed-in user's own policies fetched from the backend", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        policies: [
          {
            id: 123,
            plan_code: "seismic",
            station_code: "seismic_tokyo",
            payout_tier_code: "ten_thousand",
            policy_status_code: "pending",
            threshold: "0",
          },
        ],
      }),
    });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("待機中")).toBeInTheDocument();
    expect(screen.getByText("東京震度観測点")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "申込ウィザードへ" })).toBeInTheDocument();
    expect(global.fetch).toHaveBeenCalledWith("/api/v1/policies");
  });

  it("shows an empty state when the user has no policies yet", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ policies: [] }),
    });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("まだ契約がありません。申込ウィザードから作成してください。")).toBeInTheDocument();
  });

  it("prompts the visitor to log in when the session is not authenticated", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      json: async () => ({ error: "unauthorized" }),
    });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("ログインすると契約情報を確認できます。")).toBeInTheDocument();
  });

  it("shows a load-failure message and never falls back to another user's cached data", async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error("network error"));

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("契約情報の取得に失敗しました。時間をおいて再度お試しください。")).toBeInTheDocument();
  });
});
