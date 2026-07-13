'use client';

import { useMemo } from 'react';
import { useLocale, useT } from '@/lib/i18n';
import type { PayoutTier } from '@/lib/types';

export function Step4Tier({
  tiers,
  selectedTierId,
  onSelect,
  onBack,
  onNext
}: {
  tiers: PayoutTier[];
  selectedTierId: number | null;
  onSelect: (tierId: number) => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const t = useT();
  const { locale } = useLocale();
  const formatter = useMemo(
    () => new Intl.NumberFormat(locale, { style: 'currency', currency: 'JPY', maximumFractionDigits: 0 }),
    [locale]
  );

  return (
    <section className="surface-card p-6 shadow-xl">
      <h2 className="mb-2 text-2xl font-semibold">{t('wizard_step4')}</h2>
      <p className="mb-6 text-sm text-muted">{t('tier_simulated_note')}</p>
      <div className="grid gap-4 md:grid-cols-2">
        {tiers.map((tier) => {
          const selected = tier.id === selectedTierId;

          return (
            <button
              key={tier.id}
              type="button"
              className={[
                'selection-card flex flex-col items-start gap-3 p-6 text-left',
                selected ? 'selection-card-selected' : ''
              ].join(' ')}
              onClick={() => onSelect(tier.id)}
            >
              <div className="text-3xl font-semibold">{formatter.format(tier.amount_jpy)}</div>
              <div className="text-sm text-muted">{tier.label}</div>
              <div className="text-xs text-primary">{t('tier_simulated_badge')}</div>
            </button>
          );
        })}
      </div>
      <div className="mt-6 flex justify-between gap-3">
        <button type="button" className="action-button secondary-button" onClick={onBack}>
          <i className="fa-solid fa-arrow-left" aria-hidden="true" />
          <span>{t('btn_back')}</span>
        </button>
        <button type="button" className="action-button" disabled={!selectedTierId} onClick={onNext}>
          <span>{t('btn_next')}</span>
          <i className="fa-solid fa-arrow-right" aria-hidden="true" />
        </button>
      </div>
    </section>
  );
}
