import { getMessages, SUPPORTED_LOCALES } from "@/lib/i18n";

describe("i18n", () => {
  it("supports seven locales", () => {
    expect(SUPPORTED_LOCALES).toHaveLength(7);
    expect(SUPPORTED_LOCALES).toEqual(["ja", "en", "fr", "zh", "ru", "es", "ar"]);
  });

  it("falls back to Japanese for unknown locales", () => {
    expect(getMessages("xx").banner.notice).toContain("模擬デモ");
  });
});
