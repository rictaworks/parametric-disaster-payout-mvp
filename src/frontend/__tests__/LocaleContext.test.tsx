import { render, screen, waitFor } from "@testing-library/react";
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

function TwoWayLocaleSwitcher() {
  const { setLocale } = useLocale();

  return (
    <>
      <button onClick={() => setLocale("en")}>to en</button>
      <button onClick={() => setLocale("fr")}>to fr</button>
    </>
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

  it("serializes sync requests so a slow earlier request cannot overwrite a later locale selection (race condition regression)", async () => {
    let resolveEn: (value: { ok: boolean; status: number; json: () => Promise<unknown> }) => void = () => undefined;
    const enResponse = new Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>((resolve) => {
      resolveEn = resolve;
    });

    const sentLocales: string[] = [];
    const fetchMock = jest.fn().mockImplementation((_input: RequestInfo | URL, init?: RequestInit) => {
      const locale = JSON.parse(init?.body as string).locale as string;
      sentLocales.push(locale);
      return locale === "en" ? enResponse : Promise.resolve({ ok: true, status: 200, json: async () => ({}) });
    });
    global.fetch = fetchMock;

    const user = userEvent.setup();
    render(
      <LocaleProvider>
        <TwoWayLocaleSwitcher />
      </LocaleProvider>
    );

    await user.click(screen.getByRole("button", { name: "to en" }));
    await user.click(screen.getByRole("button", { name: "to fr" }));

    // "fr" must not be sent until the slow "en" request settles, otherwise a fast "fr"
    // response could persist before the (stale) "en" request completes and overwrites it
    expect(sentLocales).toEqual(["en"]);

    resolveEn({ ok: true, status: 200, json: async () => ({}) });

    await waitFor(() => expect(sentLocales).toEqual(["en", "fr"]));
  });
});
