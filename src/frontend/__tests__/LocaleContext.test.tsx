import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LocaleProvider, useLocale } from "../components/LocaleContext";

function LocaleSwitcher() {
  const { locale, setLocale } = useLocale();

  return (
    <button onClick={() => setLocale("en")}>
      current: {locale}
    </button>
  );
}

describe("LocaleContext", () => {
  afterEach(() => {
    jest.restoreAllMocks();
    window.localStorage.clear();
  });

  it("syncs the newly selected locale to the backend when the user switches language", async () => {
    const fetchMock = jest.fn().mockResolvedValue({ ok: true, status: 200, json: async () => ({}) });
    global.fetch = fetchMock;

    const user = userEvent.setup();
    render(
      <LocaleProvider>
        <LocaleSwitcher />
      </LocaleProvider>
    );

    await user.click(screen.getByRole("button"));

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/locale",
      expect.objectContaining({
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ locale: "en" }),
      })
    );
  });

  it("does not throw when the backend sync fails (e.g. not logged in yet)", async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error("network error"));

    const user = userEvent.setup();
    render(
      <LocaleProvider>
        <LocaleSwitcher />
      </LocaleProvider>
    );

    await user.click(screen.getByRole("button"));

    expect(await screen.findByText("current: en")).toBeInTheDocument();
  });
});
