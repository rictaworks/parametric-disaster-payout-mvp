'use client';

import { useMemo, useState } from 'react';
import ReCAPTCHA from 'react-google-recaptcha';
import { useRouter } from 'next/navigation';
import { createPolicy } from '@/lib/api';
import { useLocale, useT } from '@/lib/i18n';
import type { Plan, PayoutTier, Station, WizardState } from '@/lib/types';

const ageOptions = ['under_20', '20s', '30s', '40s', '50s', '60s', 'over_70'] as const;

export function Step5Confirm({
  state,
  selectedPlan,
  selectedStation,
  selectedThresholdLabel,
  selectedTier,
  onBack,
  updateState
}: {
  state: WizardState;
  selectedPlan: Plan;
  selectedStation: Station;
  selectedThresholdLabel: string;
  selectedTier: PayoutTier;
  onBack: () => void;
  updateState: (partial: Partial<WizardState>) => void;
}) {
  const t = useT();
  const { locale } = useLocale();
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const formatter = useMemo(
    () => new Intl.NumberFormat(locale, { style: 'currency', currency: 'JPY', maximumFractionDigits: 0 }),
    [locale]
  );

  const handleSubmit = async () => {
    if (!state.recaptchaToken) {
      setError(t('error_recaptcha_required'));
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      await createPolicy({
        plan_id: selectedPlan.id,
        station_id: selectedStation.id,
        threshold: state.threshold,
        payout_tier_id: selectedTier.id,
        age_group: state.ageGroup,
        recaptcha_token: state.recaptchaToken,
        locale
      });
      router.push('/dashboard');
    } catch (caught) {
      const status = (caught as { status?: number }).status;
      if (status === 409) {
        setError(t('error_duplicate_policy'));
      } else {
        setError(t('error_general'));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <section className="surface-card p-6 shadow-xl">
      <h2 className="mb-6 text-2xl font-semibold">{t('confirm_title')}</h2>
      <table className="summary-table mb-6">
        <tbody>
          <tr>
            <th>{t('confirm_plan')}</th>
            <td>{selectedPlan.label}</td>
          </tr>
          <tr>
            <th>{t('confirm_station')}</th>
            <td>{selectedStation.label}</td>
          </tr>
          <tr>
            <th>{t('confirm_threshold')}</th>
            <td>{selectedThresholdLabel}</td>
          </tr>
          <tr>
            <th>{t('confirm_tier')}</th>
            <td>{formatter.format(selectedTier.amount_jpy)}</td>
          </tr>
        </tbody>
      </table>

      <div className="mb-6 grid gap-3">
        <label className="grid gap-2 text-sm">
          <span>{t('confirm_age_group')}</span>
          <select
            className="px-3 py-3"
            value={state.ageGroup ?? ''}
            onChange={(event) => updateState({ ageGroup: event.target.value || null })}
          >
            <option value="">{t('confirm_age_prefer_not')}</option>
            {ageOptions.map((ageKey) => (
              <option key={ageKey} value={ageKey}>
                {t(`age_${ageKey}`)}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="mb-4 grid gap-3">
        <ReCAPTCHA
          sitekey={process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY ?? 'test-key'}
          onChange={(token) => updateState({ recaptchaToken: token })}
        />
        <div className="text-sm text-muted">{t('recaptcha_note')}</div>
      </div>

      {error ? (
        <div className="mb-4 border border-error/50 bg-error/10 px-4 py-3 text-sm text-error">{error}</div>
      ) : null}

      <div className="flex justify-between gap-3">
        <button type="button" className="action-button secondary-button" onClick={onBack} disabled={submitting}>
          <i className="fa-solid fa-arrow-left" aria-hidden="true" />
          <span>{t('btn_back')}</span>
        </button>
        <button type="button" className="action-button" onClick={handleSubmit} disabled={submitting || !state.recaptchaToken}>
          {submitting ? <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> : <i className="fa-solid fa-paper-plane" aria-hidden="true" />}
          <span>{t('btn_submit')}</span>
        </button>
      </div>
    </section>
  );
}
