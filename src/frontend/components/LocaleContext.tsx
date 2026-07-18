"use client";

import type { ReactNode } from "react";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  DEFAULT_LOCALE,
  LOCALE_STORAGE_KEY,
  SUPPORTED_LOCALES,
  type Locale,
  type Messages,
  getMessages,
  getTextDirection,
} from "@/lib/i18n";
import { syncLocalePreference } from "@/lib/locale-api";

type LocaleContextValue = {
  locale: Locale;
  messages: Messages;
  setLocale: (locale: Locale) => void;
};

const LocaleContext = createContext<LocaleContextValue>({
  locale: DEFAULT_LOCALE,
  messages: getMessages(DEFAULT_LOCALE),
  setLocale: () => undefined,
});

export function useLocale() {
  return useContext(LocaleContext);
}

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(() => {
    if (typeof window === "undefined") {
      return DEFAULT_LOCALE;
    }

    const storedLocale = window.localStorage.getItem(LOCALE_STORAGE_KEY);
    return storedLocale && SUPPORTED_LOCALES.includes(storedLocale as Locale)
      ? (storedLocale as Locale)
      : DEFAULT_LOCALE;
  });

  useEffect(() => {
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
    document.documentElement.lang = locale;
    document.documentElement.dir = getTextDirection(locale);
  }, [locale]);

  const setLocale = useCallback((newLocale: Locale) => {
    setLocaleState(newLocale);
    // 選好言語をUser#localeへ同期する（未ログイン時は401になるがベストエフォートで無視する）
    void syncLocalePreference(newLocale);
  }, []);

  const value = useMemo<LocaleContextValue>(() => {
    return {
      locale,
      messages: getMessages(locale),
      setLocale,
    };
  }, [locale, setLocale]);

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}
