'use client';

import { useT } from '@/lib/i18n';
import type { Threshold } from '@/lib/types';

export function Step3Threshold({
  thresholds,
  selectedThreshold,
  isSeismic,
  onSelect,
  onBack,
  onNext
}: {
  thresholds: Threshold[];
  selectedThreshold: string | null;
  isSeismic: boolean;
  onSelect: (thresholdCode: string) => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const t = useT();

  return (
    <section className="surface-card p-6 shadow-xl">
      <h2 className="mb-2 text-2xl font-semibold">{t('wizard_step3')}</h2>
      <p className="mb-6 text-sm text-muted">{t('threshold_title')}</p>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {thresholds.map((threshold) => {
          const selected = threshold.code === selectedThreshold;
          const label = isSeismic
            ? t('threshold_seismic_label', { value: threshold.label })
            : t('threshold_rainfall_label', { value: String(threshold.value) });

          return (
            <button
              key={threshold.code}
              type="button"
              className={[
                'selection-card flex flex-col items-start gap-3 p-5 text-left',
                selected ? 'selection-card-selected' : ''
              ].join(' ')}
              onClick={() => onSelect(threshold.code)}
            >
              <div className="text-2xl font-semibold">{threshold.label}</div>
              <div className="text-sm text-muted">{label}</div>
            </button>
          );
        })}
      </div>
      <div className="mt-6 flex justify-between gap-3">
        <button type="button" className="action-button secondary-button" onClick={onBack}>
          <i className="fa-solid fa-arrow-left" aria-hidden="true" />
          <span>{t('btn_back')}</span>
        </button>
        <button type="button" className="action-button" disabled={!selectedThreshold} onClick={onNext}>
          <span>{t('btn_next')}</span>
          <i className="fa-solid fa-arrow-right" aria-hidden="true" />
        </button>
      </div>
    </section>
  );
}
