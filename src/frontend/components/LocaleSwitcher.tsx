'use client';

import { useLocale, localeOptions, useT } from '@/lib/i18n';

export function LocaleSwitcher() {
  const { locale, setLocale } = useLocale();
  const t = useT();

  return (
    <label className="flex items-center gap-3 text-sm">
      <i className="fa-solid fa-language text-primary" aria-hidden="true" />
      <select
        className="min-w-40 px-3 py-2"
        value={locale}
        onChange={(event) => setLocale(event.target.value)}
      >
        {localeOptions.map((option) => (
          <option key={option} value={option}>
            {t(`lang_${option}`)}
          </option>
        ))}
      </select>
    </label>
  );
}
