import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LocaleProvider } from "../components/LocaleContext";
import { LoginForm } from "../components/LoginForm";

describe("LoginForm", () => {
  afterEach(() => {
    jest.restoreAllMocks();
    window.localStorage.clear();
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

    const user = userEvent.setup();
    render(
      <LocaleProvider>
        <LoginForm />
      </LocaleProvider>
    );

    await user.type(screen.getByRole("textbox"), "dummy-id-token");
    await user.click(screen.getByRole("button"));

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
    global.fetch = jest.fn().mockResolvedValue({ ok: false, status: 401, json: async () => ({}) });

    const user = userEvent.setup();
    render(
      <LocaleProvider>
        <LoginForm />
      </LocaleProvider>
    );

    await user.type(screen.getByRole("textbox"), "dummy-id-token");
    await user.click(screen.getByRole("button"));

    await screen.findByText("ログインに失敗しました。");

    expect(global.fetch).not.toHaveBeenCalledWith("/api/v1/locale", expect.anything());
  });
});
