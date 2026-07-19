import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LocaleProvider, useLocale } from "../components/LocaleContext";
import { LoginForm } from "../components/LoginForm";

type GoogleCredentialResponse = {
  credential?: string;
};

function installGoogleIdentityServicesMock() {
  const renderButton = jest.fn((container: HTMLElement) => {
    container.replaceChildren();

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Googleでログイン";
    container.appendChild(button);
  });

  let callback: ((response: GoogleCredentialResponse) => void) | undefined;
  const initialize = jest.fn((config: { client_id: string; callback: (response: GoogleCredentialResponse) => void }) => {
    callback = config.callback;
  });

  (window as typeof window & {
    google?: {
      accounts?: {
        id?: {
          initialize: typeof initialize;
          renderButton: typeof renderButton;
        };
      };
    };
  }).google = {
    accounts: {
      id: {
        initialize,
        renderButton,
      },
    },
  };

  return {
    initialize,
    renderButton,
    triggerCredentialResponse(response: GoogleCredentialResponse) {
      if (!callback) {
        throw new Error("Google callback was not initialized");
      }

      callback(response);
    },
  };
}

describe("LoginForm", () => {
  afterEach(() => {
    jest.restoreAllMocks();
    window.localStorage.clear();
    delete (window as typeof window & { google?: unknown }).google;
    document.getElementById("google-identity-services-script")?.remove();
  });

  it("syncs the current locale to the backend right after a successful login", async () => {
    const fetchMock = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = input.toString();

      if (url === "/api/v1/session") {
        return Promise.resolve({ ok: true, status: 200, json: async () => ({}) });
      }

      return Promise.resolve({ ok: true, status: 200, json: async () => ({}) });
    });
    global.fetch = fetchMock;

    const google = installGoogleIdentityServicesMock();
    render(
      <LocaleProvider>
        <LoginForm />
      </LocaleProvider>
    );

    await waitFor(() => expect(google.initialize).toHaveBeenCalled());
    await act(async () => {
      google.triggerCredentialResponse({ credential: "dummy-id-token" });
    });

    await screen.findByText("ログインに成功しました。");

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/locale",
      expect.objectContaining({
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ locale: "ja" }),
      })
    );
  });

  it("does not sync locale when login fails", async () => {
    global.fetch = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = input.toString();

      if (url === "/api/v1/session") {
        return Promise.resolve({ ok: false, status: 401, json: async () => ({}) });
      }

      return Promise.resolve({ ok: true, status: 200, json: async () => ({}) });
    });

    const google = installGoogleIdentityServicesMock();
    render(
      <LocaleProvider>
        <LoginForm />
      </LocaleProvider>
    );

    await waitFor(() => expect(google.initialize).toHaveBeenCalled());
    await act(async () => {
      google.triggerCredentialResponse({ credential: "dummy-id-token" });
    });

    await screen.findByText("ログインに失敗しました。");

    expect(global.fetch).not.toHaveBeenCalledWith("/api/v1/locale", expect.anything());
  });

  it("syncs the locale current at the moment login succeeds, not the one captured when the form was submitted (stale-closure race regression)", async () => {
    let resolveSession: (value: { ok: boolean; status: number; json: () => Promise<unknown> }) => void = () => undefined;
    const sessionResponse = new Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>((resolve) => {
      resolveSession = resolve;
    });

    const localeCalls: string[] = [];
    const fetchMock = jest.fn().mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
      const url = input.toString();

      if (url === "/api/v1/session") {
        return sessionResponse;
      }

      localeCalls.push(JSON.parse(init?.body as string).locale);
      return Promise.resolve({ ok: true, status: 200, json: async () => ({}) });
    });
    global.fetch = fetchMock;

    const google = installGoogleIdentityServicesMock();

    function Harness() {
      const { setLocale } = useLocale();
      return (
        <>
          <LoginForm />
          <button onClick={() => setLocale("fr")}>switch to fr</button>
        </>
      );
    }

    const user = userEvent.setup();
    render(
      <LocaleProvider>
        <Harness />
      </LocaleProvider>
    );

    await waitFor(() => expect(google.initialize).toHaveBeenCalled());
    await act(async () => {
      google.triggerCredentialResponse({ credential: "dummy-id-token" });
    });

    // ユーザーはログイン処理が完了する前に言語を切り替える
    await user.click(screen.getByRole("button", { name: "switch to fr" }));

    resolveSession({ ok: true, status: 200, json: async () => ({}) });
    await screen.findByText("ログインに成功しました。");

    expect(localeCalls[localeCalls.length - 1]).toBe("fr");
  });
});
