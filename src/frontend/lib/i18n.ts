'use client';

import type { ReactNode } from 'react';
import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import ja from '@/locales/ja.json';
import en from '@/locales/en.json';
import fr from '@/locales/fr.json';
import zh from '@/locales/zh.json';
import ru from '@/locales/ru.json';
import es from '@/locales/es.json';
import ar from '@/locales/ar.json';

const messages = { ja, en, fr, zh, ru, es, ar };

export const localeOptions = ['ja', 'en', 'fr', 'zh', 'ru', 'es', 'ar'] as const;
export type Locale = (typeof localeOptions)[number];
type MessageKey = keyof typeof ja;

type LocaleContextValue = {
  locale: Locale;
  setLocale: (locale: string) => void;
  dictionary: typeof ja;
};

const LocaleContext = createContext<LocaleContextValue | null>(null);

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>('ja');

  useEffect(() => {
    const stored = window.localStorage.getItem('locale');
    if (stored && localeOptions.includes(stored as Locale)) {
      setLocaleState(stored as Locale);
    }
  }, []);

  const setLocale = (nextLocale: string) => {
    if (localeOptions.includes(nextLocale as Locale)) {
      const safeLocale = nextLocale as Locale;
      setLocaleState(safeLocale);
      window.localStorage.setItem('locale', safeLocale);
      document.documentElement.lang = safeLocale;
      document.documentElement.dir = safeLocale === 'ar' ? 'rtl' : 'ltr';
    }
  };

  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dir = locale === 'ar' ? 'rtl' : 'ltr';
  }, [locale]);

  const value = useMemo(
    () => ({ locale, setLocale, dictionary: messages[locale] }),
    [locale]
  );

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useLocale() {
  const context = useContext(LocaleContext);
  if (!context) {
    throw new Error('LocaleContextUnavailable');
  }
  return context;
}

export function useT() {
  const { dictionary } = useLocale();

  return (key: MessageKey | string, values?: Record<string, string | number>) => {
    const template = dictionary[key as MessageKey] ?? String(key);
    if (!values) {
      return template;
    }

    return Object.entries(values).reduce(
      (result, [name, value]) => result.replaceAll(`{${name}}`, String(value)),
      template
    );
  };
}
