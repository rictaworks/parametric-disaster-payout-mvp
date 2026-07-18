"use client";

import type { ReactNode } from "react";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
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
  // ログイン処理中に言語が切り替わるレースを避けるため、非同期処理の完了後に
  // 「その時点で最新のlocale」を読み直すためのアクセサ（クロージャの値ではなくrefを返す）
  getLocale: () => Locale;
};

const LocaleContext = createContext<LocaleContextValue>({
  locale: DEFAULT_LOCALE,
  messages: getMessages(DEFAULT_LOCALE),
  setLocale: () => undefined,
  getLocale: () => DEFAULT_LOCALE,
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

  const localeRef = useRef(locale);
  useEffect(() => {
    localeRef.current = locale;
  }, [locale]);
  const getLocale = useCallback(() => localeRef.current, []);

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
      getLocale,
    };
  }, [locale, setLocale, getLocale]);

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}
