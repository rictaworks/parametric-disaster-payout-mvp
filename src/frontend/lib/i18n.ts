import ar from "@/locales/ar.json";
import en from "@/locales/en.json";
import es from "@/locales/es.json";
import fr from "@/locales/fr.json";
import ja from "@/locales/ja.json";
import ru from "@/locales/ru.json";
import zh from "@/locales/zh.json";

export const SUPPORTED_LOCALES = ["ja", "en", "fr", "zh", "ru", "es", "ar"] as const;

export type Locale = (typeof SUPPORTED_LOCALES)[number];
export type Messages = typeof ja;

export const DEFAULT_LOCALE: Locale = "ja";
export const LOCALE_STORAGE_KEY = "parametric-disaster-payout-locale";
const RTL_LOCALES: readonly Locale[] = ["ar"];

export function getTextDirection(locale: Locale): "rtl" | "ltr" {
  return RTL_LOCALES.includes(locale) ? "rtl" : "ltr";
}

const messagesByLocale: Record<Locale, Messages> = {
  ja,
  en,
  fr,
  zh,
  ru,
  es,
  ar,
};

export function isLocale(value: string): value is Locale {
  return SUPPORTED_LOCALES.includes(value as Locale);
}

export function getMessages(locale: string | null | undefined): Messages {
  const normalizedLocale = locale ?? "";

  return isLocale(normalizedLocale)
    ? messagesByLocale[normalizedLocale]
    : messagesByLocale[DEFAULT_LOCALE];
}

export function formatLocaleLabel(locale: Locale, messages: Messages): string {
  return messages.language.options[locale];
}
