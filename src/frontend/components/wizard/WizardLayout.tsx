'use client';

import { useEffect, useMemo, useState } from 'react';
import { fetchPayoutTiers, fetchPlans, fetchStations } from '@/lib/api';
import { useLocale, useT } from '@/lib/i18n';
import type { PayoutTier, Plan, Station, Threshold, WizardState } from '@/lib/types';
import { Step1Plan } from '@/components/wizard/Step1Plan';
import { Step2Station } from '@/components/wizard/Step2Station';
import { Step3Threshold } from '@/components/wizard/Step3Threshold';
import { Step4Tier } from '@/components/wizard/Step4Tier';
import { Step5Confirm } from '@/components/wizard/Step5Confirm';
import { StepBar } from '@/components/wizard/StepBar';

const initialState: WizardState = {
  step: 1,
  planId: null,
  stationId: null,
  threshold: null,
  payoutTierId: null,
  ageGroup: null,
  recaptchaToken: null
};

const seismicThresholds: Threshold[] = [
  { code: 'int_5_lower', label: '', value: '5_lower' },
  { code: 'int_5_upper', label: '', value: '5_upper' },
  { code: 'int_6_lower', label: '', value: '6_lower' },
  { code: 'int_6_upper', label: '', value: '6_upper' },
  { code: 'int_7', label: '', value: '7' }
];

const rainfallThresholds: Threshold[] = [
  { code: 'rain_50', label: '', value: 50 },
  { code: 'rain_100', label: '', value: 100 },
  { code: 'rain_150', label: '', value: 150 },
  { code: 'rain_200', label: '', value: 200 }
];

export function WizardLayout() {
  const t = useT();
  const { locale } = useLocale();
  const [state, setState] = useState<WizardState>(initialState);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [stations, setStations] = useState<Station[]>([]);
  const [tiers, setTiers] = useState<PayoutTier[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    Promise.all([fetchPlans(locale), fetchStations(locale), fetchPayoutTiers(locale)])
      .then(([loadedPlans, loadedStations, loadedTiers]) => {
        setPlans(loadedPlans);
        setStations(loadedStations);
        setTiers(loadedTiers);
      })
      .finally(() => setLoading(false));
  }, [locale]);

  const selectedPlan = useMemo(
    () => plans.find((plan) => plan.id === state.planId) ?? null,
    [plans, state.planId]
  );
  const filteredStations = useMemo(
    () => stations.filter((station) => station.plan_type === selectedPlan?.plan_type),
    [selectedPlan?.plan_type, stations]
  );
  const selectedStation = useMemo(
    () => stations.find((station) => station.id === state.stationId) ?? null,
    [state.stationId, stations]
  );
  const thresholds = (selectedPlan?.plan_type === 'rainfall' ? rainfallThresholds : seismicThresholds).map((threshold) => ({
    ...threshold,
    label: t(`threshold_option_${threshold.code}`)
  }));
  const selectedTier = useMemo(
    () => tiers.find((tier) => tier.id === state.payoutTierId) ?? null,
    [state.payoutTierId, tiers]
  );
  const selectedThreshold = thresholds.find((threshold) => threshold.code === state.threshold) ?? null;
  const selectedThresholdLabel = selectedThreshold
    ? selectedPlan?.plan_type === 'rainfall'
      ? t('threshold_rainfall_label', { value: String(selectedThreshold.value) })
      : t('threshold_seismic_label', { value: selectedThreshold.label })
    : '';

  const updateState = (partial: Partial<WizardState>) => {
    setState((current) => ({ ...current, ...partial }));
  };

  const selectPlan = (planId: number) => {
    setState((current) => ({
      ...current,
      planId,
      stationId: null,
      threshold: null,
      payoutTierId: null,
      recaptchaToken: null
    }));
  };

  if (loading) {
    return (
      <main className="mx-auto flex min-h-[calc(100vh-7rem)] max-w-5xl items-center justify-center px-4">
        <i className="fa-solid fa-spinner fa-spin text-2xl text-primary" aria-hidden="true" />
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-6xl px-4 py-10">
      <div className="mb-8">
        <h1 className="mb-2 text-3xl font-semibold">{t('wizard_title')}</h1>
      </div>
      <StepBar currentStep={state.step} />
      {state.step === 1 ? (
        <Step1Plan
          plans={plans}
          selectedPlanId={state.planId}
          onSelect={selectPlan}
          onNext={() => updateState({ step: 2 })}
        />
      ) : null}
      {state.step === 2 ? (
        <Step2Station
          stations={filteredStations}
          selectedStationId={state.stationId}
          onSelect={(stationId) => updateState({ stationId, threshold: null, payoutTierId: null, recaptchaToken: null })}
          onBack={() => updateState({ step: 1 })}
          onNext={() => updateState({ step: 3 })}
        />
      ) : null}
      {state.step === 3 && selectedPlan ? (
        <Step3Threshold
          thresholds={thresholds}
          selectedThreshold={state.threshold}
          isSeismic={selectedPlan.plan_type === 'seismic'}
          onSelect={(threshold) => updateState({ threshold, payoutTierId: null, recaptchaToken: null })}
          onBack={() => updateState({ step: 2 })}
          onNext={() => updateState({ step: 4 })}
        />
      ) : null}
      {state.step === 4 ? (
        <Step4Tier
          tiers={tiers}
          selectedTierId={state.payoutTierId}
          onSelect={(payoutTierId) => updateState({ payoutTierId, recaptchaToken: null })}
          onBack={() => updateState({ step: 3 })}
          onNext={() => updateState({ step: 5 })}
        />
      ) : null}
      {state.step === 5 && selectedPlan && selectedStation && selectedTier && selectedThreshold ? (
        <Step5Confirm
          state={state}
          selectedPlan={selectedPlan}
          selectedStation={selectedStation}
          selectedThresholdLabel={selectedThresholdLabel}
          selectedTier={selectedTier}
          onBack={() => updateState({ step: 4 })}
          updateState={updateState}
        />
      ) : null}
    </main>
  );
}
