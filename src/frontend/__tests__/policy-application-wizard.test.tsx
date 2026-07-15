import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "../components/AppShell";
import NewPolicyPage from "../app/policies/new/page";

const pushMock = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({
    push: pushMock,
  }),
}));

const MASTERS_RESPONSE = {
  plans: [
    { id: 11, code: "seismic", trigger_type: "seismic" },
    { id: 12, code: "rainfall", trigger_type: "rainfall" },
  ],
  stations: [
    { id: 21, code: "seismic_tokyo", measurement_type: "seismic" },
    { id: 22, code: "seismic_osaka", measurement_type: "seismic" },
    { id: 23, code: "rainfall_tokyo", measurement_type: "rainfall" },
  ],
  payout_tiers: [
    { id: 31, code: "ten_thousand", amount_yen: 10_000 },
    { id: 32, code: "thirty_thousand", amount_yen: 30_000 },
  ],
};

type RecaptchaCallback = (token: string) => void;

function mockFetch(policyResponse: { ok: boolean; body: unknown }) {
  const calls: Array<{ url: string; init?: RequestInit }> = [];

  global.fetch = jest.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });

    if (url.includes("/api/v1/masters")) {
      return Promise.resolve({
        ok: true,
        json: async () => MASTERS_RESPONSE,
      }) as unknown as Promise<Response>;
    }

    return Promise.resolve({
      ok: policyResponse.ok,
      text: async () => JSON.stringify(policyResponse.body),
    }) as unknown as Promise<Response>;
  }) as jest.Mock;

  return calls;
}

function mockRecaptcha() {
  let callback: RecaptchaCallback | null = null;
  const resetMock = jest.fn();
  const renderMock = jest.fn((_container: HTMLElement, params: { callback: RecaptchaCallback }) => {
    callback = params.callback;
    return 1;
  });

  window.grecaptcha = { render: renderMock, reset: resetMock };

  return {
    verify: (token: string) => {
      act(() => {
        callback?.(token);
      });
    },
    renderMock,
    resetMock,
  };
}

async function advanceToReviewStep(user: ReturnType<typeof userEvent.setup>) {
  for (let index = 0; index < 4; index += 1) {
    await user.click(screen.getByRole("button", { name: "次へ" }));
  }
}

describe("Policy application wizard", () => {
  beforeEach(() => {
    pushMock.mockReset();
    delete (window as { grecaptcha?: unknown }).grecaptcha;
  });

  it("shows the five-step flow, loads masters, requires reCAPTCHA, and redirects to my page after submission", async () => {
    const calls = mockFetch({ ok: true, body: { policy: { id: 123 } } });
    const recaptcha = mockRecaptcha();

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    const user = userEvent.setup();

    expect(screen.getByRole("heading", { name: "契約申込ウィザード" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "次へ" })).toBeInTheDocument();

    await advanceToReviewStep(user);

    const submitButton = screen.getByRole("button", { name: "申込する" });
    expect(submitButton).toBeDisabled();

    await waitFor(() => expect(recaptcha.renderMock).toHaveBeenCalled());
    recaptcha.verify("real-recaptcha-token");

    await waitFor(() => expect(submitButton).toBeEnabled());

    await user.click(submitButton);

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/mypage");
    });

    const mastersCall = calls.find((call) => call.url.includes("masters"));
    expect(mastersCall?.url).toBe("/api/v1/masters");

    const policyCall = calls.find((call) => call.url.includes("/api/v1/policies"));
    expect(policyCall).toBeDefined();
    const sentBody = JSON.parse(String(policyCall?.init?.body));
    expect(sentBody).toMatchObject({
      plan_id: 11,
      station_id: 21,
      payout_tier_id: 31,
      threshold: "0",
      recaptcha_token: "real-recaptcha-token",
    });
  });

  it("shows a localized duplicate-policy error and resets the reCAPTCHA challenge when the backend rejects the application", async () => {
    mockFetch({ ok: false, body: { error: "duplicate_policy" } });
    const recaptcha = mockRecaptcha();

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    const user = userEvent.setup();
    await advanceToReviewStep(user);

    await waitFor(() => expect(recaptcha.renderMock).toHaveBeenCalled());
    recaptcha.verify("real-recaptcha-token");

    const submitButton = await screen.findByRole("button", { name: "申込する" });
    await waitFor(() => expect(submitButton).toBeEnabled());
    await user.click(submitButton);

    expect(await screen.findByText("同一プラン種別の有効な契約が既にあります。")).toBeInTheDocument();
    expect(pushMock).not.toHaveBeenCalled();

    // The reCAPTCHA challenge is single-use: after a failed submission the widget
    // must be remounted (forcing a fresh verification) before the user can retry.
    await waitFor(() => expect(recaptcha.renderMock).toHaveBeenCalledTimes(2));
    expect(submitButton).toBeDisabled();
  });

  it("disables the submit button and blocks submission until the reCAPTCHA challenge is completed", async () => {
    mockFetch({ ok: true, body: { policy: { id: 123 } } });
    mockRecaptcha();

    const { container } = render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    const user = userEvent.setup();
    await advanceToReviewStep(user);

    expect(screen.getByRole("button", { name: "申込する" })).toBeDisabled();

    // The submit button is disabled without a token, so simulate a form-level
    // submit event directly to verify the handler's own defensive guard.
    const form = container.querySelector("form");
    if (form) {
      fireEvent.submit(form);
    }

    expect(await screen.findByText("reCAPTCHA の認証を完了してください。")).toBeInTheDocument();
    expect(pushMock).not.toHaveBeenCalled();
  });
});
