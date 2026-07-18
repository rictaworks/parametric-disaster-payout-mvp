import type { Locale } from "./i18n";

export async function syncLocalePreference(locale: Locale): Promise<void> {
  try {
    await fetch("/api/v1/locale", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ locale }),
    });
  } catch {
    // ベストエフォート: 未ログイン時は401になるが、言語切り替え自体は
    // localStorageで完結して成立するため、同期失敗は無視してよい
  }
}
