"use client";

import { useLocale } from "@/components/LocaleContext";
import { formatLocaleLabel, SUPPORTED_LOCALES, type Locale } from "@/lib/i18n";

export function LanguageSwitcher() {
  const { locale, messages, setLocale } = useLocale();

  return (
    <div className="language-switcher">
      <span className="language-switcher__label">{messages.language.label}</span>
      <div className="language-switcher__buttons" role="group" aria-label={messages.language.label}>
        {SUPPORTED_LOCALES.map((option) => (
          <button
            key={option}
            type="button"
            className="language-switcher__button"
            data-active={option === locale}
            aria-pressed={option === locale}
            onClick={() => setLocale(option as Locale)}
          >
            {formatLocaleLabel(option, messages)}
          </button>
        ))}
      </div>
    </div>
  );
}
