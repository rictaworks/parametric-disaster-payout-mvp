import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "../components/AppShell";
import NewPolicyPage from "../app/policies/new/page";
import { POLICY_WIZARD_STORAGE_KEY } from "../components/wizard/policyWizardData";

const pushMock = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({
    push: pushMock,
  }),
}));

describe("Policy application wizard", () => {
  beforeEach(() => {
    pushMock.mockReset();
    window.localStorage.clear();
  });

  it("shows the five-step flow, requires reCAPTCHA, and redirects to my page after submission", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      text: async () => JSON.stringify({ policy: { id: 123 } }),
    });

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    const user = userEvent.setup();

    expect(screen.getByRole("heading", { name: "契約申込ウィザード" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "次へ" })).toBeInTheDocument();

    for (let index = 0; index < 4; index += 1) {
      await user.click(screen.getByRole("button", { name: "次へ" }));
    }

    const submitButton = screen.getByRole("button", { name: "申込する" });
    expect(submitButton).toBeDisabled();
    expect(screen.getByRole("checkbox", { name: /reCAPTCHA チェックボックス/ })).toBeInTheDocument();

    await user.click(screen.getByRole("checkbox", { name: /reCAPTCHA チェックボックス/ }));
    expect(submitButton).toBeEnabled();

    await user.click(submitButton);

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/mypage");
    });

    const saved = JSON.parse(window.localStorage.getItem(POLICY_WIZARD_STORAGE_KEY) ?? "{}");
    expect(saved).toMatchObject({
      policyId: 123,
      statusLabel: "待機中",
      planLabel: "震度連動",
      stationLabel: "東京震度観測点",
      thresholdLabel: "0",
      payoutTierLabel: "1万円相当（模擬）",
      ageGroupLabel: "未選択",
    });
  });

  it("shows a localized duplicate-policy error when the backend rejects a second application", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      text: async () => JSON.stringify({ error: "duplicate_policy" }),
    });

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    const user = userEvent.setup();
    for (let index = 0; index < 4; index += 1) {
      await user.click(screen.getByRole("button", { name: "次へ" }));
    }

    await user.click(screen.getByRole("checkbox", { name: /reCAPTCHA チェックボックス/ }));
    await user.click(screen.getByRole("button", { name: "申込する" }));

    expect(await screen.findByText("同一プラン種別の有効な契約が既にあります。")).toBeInTheDocument();
    expect(pushMock).not.toHaveBeenCalled();
  });
});
