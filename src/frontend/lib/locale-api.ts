import type { Locale } from "./i18n";

async function sendLocalePatch(locale: Locale): Promise<void> {
  try {
    await fetch("/api/v1/locale", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ locale }),
    });
  } catch {
    // ベストエフォート: 未ログイン時は401になるが、言語切り替え自体は
    // localStorageで完結して成立するため、同期失敗は無視してよい。
    // 失敗しても次回のsetLocale/ログイン時に最新値で再送される
  }
}

class LocalePreferenceSync {
  private queue: Promise<void> = Promise.resolve();

  // 直前の同期リクエストが完了してから次を送ることで、ネットワークの
  // 応答順序に関わらず最後に選択したlocaleが最後にDBへ反映されるようにする
  sync(locale: Locale): Promise<void> {
    this.queue = this.queue.then(() => sendLocalePatch(locale));
    return this.queue;
  }
}

const localePreferenceSync = new LocalePreferenceSync();

export function syncLocalePreference(locale: Locale): Promise<void> {
  return localePreferenceSync.sync(locale);
}
