import { render, screen } from "@testing-library/react";
import { AppShell } from "../components/AppShell";
import MyPage from "../app/mypage/page";
import { POLICY_WIZARD_STORAGE_KEY } from "../components/wizard/policyWizardData";

describe("My page", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("renders the latest stored simulated policy", async () => {
    window.localStorage.setItem(
      POLICY_WIZARD_STORAGE_KEY,
      JSON.stringify({
        policyId: 123,
        statusKey: "pending",
        statusLabel: "待機中",
        planLabel: "震度連動",
        stationLabel: "東京震度観測点",
        thresholdLabel: "0",
        payoutTierLabel: "1万円相当（模擬）",
        ageGroupLabel: "未選択",
        submittedAt: new Date().toISOString(),
      })
    );

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("待機中")).toBeInTheDocument();
    expect(screen.getByText("東京震度観測点")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "申込ウィザードへ" })).toBeInTheDocument();
  });
});

