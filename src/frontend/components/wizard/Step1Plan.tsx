'use client';

import { useT } from '@/lib/i18n';
import type { Plan } from '@/lib/types';

export function Step1Plan({
  plans,
  selectedPlanId,
  onSelect,
  onNext
}: {
  plans: Plan[];
  selectedPlanId: number | null;
  onSelect: (planId: number) => void;
  onNext: () => void;
}) {
  const t = useT();

  return (
    <section className="surface-card p-6 shadow-xl">
      <h2 className="mb-6 text-2xl font-semibold">{t('wizard_step1')}</h2>
      <div className="grid gap-4 md:grid-cols-2">
        {plans.map((plan) => {
          const selected = plan.id === selectedPlanId;
          const iconClass = plan.plan_type === 'seismic' ? 'fa-house-crack' : 'fa-cloud-rain';
          const descriptionKey = plan.plan_type === 'seismic' ? 'plan_seismic_desc' : 'plan_rainfall_desc';

          return (
            <button
              key={plan.id}
              type="button"
              className={[
                'selection-card flex flex-col items-start gap-4 p-6 text-left',
                selected ? 'selection-card-selected' : ''
              ].join(' ')}
              onClick={() => onSelect(plan.id)}
            >
              <i className={`fa-solid ${iconClass} text-3xl text-primary`} aria-hidden="true" />
              <div className="text-xl font-semibold">{plan.label}</div>
              <div className="text-sm text-muted">{t(descriptionKey)}</div>
            </button>
          );
        })}
      </div>
      <div className="mt-6 flex justify-end">
        <button type="button" className="action-button" disabled={!selectedPlanId} onClick={onNext}>
          <span>{t('btn_next')}</span>
          <i className="fa-solid fa-arrow-right" aria-hidden="true" />
        </button>
      </div>
    </section>
  );
}
