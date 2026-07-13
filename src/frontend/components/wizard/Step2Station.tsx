'use client';

import { useT } from '@/lib/i18n';
import type { Station } from '@/lib/types';

export function Step2Station({
  stations,
  selectedStationId,
  onSelect,
  onBack,
  onNext
}: {
  stations: Station[];
  selectedStationId: number | null;
  onSelect: (stationId: number) => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const t = useT();

  return (
    <section className="surface-card p-6 shadow-xl">
      <h2 className="mb-6 text-2xl font-semibold">{t('wizard_step2')}</h2>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {stations.map((station) => {
          const selected = station.id === selectedStationId;

          return (
            <button
              key={station.id}
              type="button"
              className={[
                'selection-card flex flex-col items-start gap-3 p-5 text-left',
                selected ? 'selection-card-selected' : ''
              ].join(' ')}
              onClick={() => onSelect(station.id)}
            >
              <div className="text-lg font-semibold">{station.label}</div>
              <div className="text-sm text-muted">{station.prefecture}</div>
              <div className="text-xs text-primary">{station.code}</div>
            </button>
          );
        })}
      </div>
      <div className="mt-6 flex justify-between gap-3">
        <button type="button" className="action-button secondary-button" onClick={onBack}>
          <i className="fa-solid fa-arrow-left" aria-hidden="true" />
          <span>{t('btn_back')}</span>
        </button>
        <button type="button" className="action-button" disabled={!selectedStationId} onClick={onNext}>
          <span>{t('btn_next')}</span>
          <i className="fa-solid fa-arrow-right" aria-hidden="true" />
        </button>
      </div>
    </section>
  );
}
