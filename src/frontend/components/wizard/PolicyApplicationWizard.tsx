"use client";

import type { FormEvent } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useLocale } from "@/components/LocaleContext";
import { RecaptchaWidget } from "./RecaptchaWidget";
import {
  fetchPolicyMasters,
  POLICY_AGE_GROUP_OPTIONS,
  POLICY_PAYOUT_TIER_OPTIONS,
  POLICY_PLAN_OPTIONS,
  POLICY_STATION_OPTIONS,
  POLICY_THRESHOLD_OPTIONS,
  type PolicyAgeGroupValue,
  type PolicyMasters,
} from "./policyWizardData";

type WizardStep = 0 | 1 | 2 | 3 | 4;

const RECAPTCHA_SITE_KEY = process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY;

export function PolicyApplicationWizard() {
  const { messages } = useLocale();
  const router = useRouter();

  const [step, setStep] = useState<WizardStep>(0);
  const [planKey, setPlanKey] = useState<string>(POLICY_PLAN_OPTIONS[0].key);
  const [stationKey, setStationKey] = useState<string>(POLICY_STATION_OPTIONS.seismic[0].key);
  const [thresholdValue, setThresholdValue] = useState<string>(POLICY_THRESHOLD_OPTIONS.seismic[0].value);
  const [payoutTierKey, setPayoutTierKey] = useState<string>(POLICY_PAYOUT_TIER_OPTIONS[0].key);
  const [ageGroupValue, setAgeGroupValue] = useState<PolicyAgeGroupValue>("");
  const [recaptchaToken, setRecaptchaToken] = useState<string | null>(null);
  const [recaptchaResetKey, setRecaptchaResetKey] = useState(0);
  const [statusMessage, setStatusMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [masters, setMasters] = useState<PolicyMasters | null>(null);
  const [mastersError, setMastersError] = useState(false);

  useEffect(() => {
    let cancelled = false;

    fetchPolicyMasters()
      .then((result) => {
        if (!cancelled) {
          setMasters(result);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setMastersError(true);
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const selectedPlan = useMemo(
    () => POLICY_PLAN_OPTIONS.find((option) => option.key === planKey) ?? POLICY_PLAN_OPTIONS[0],
    [planKey]
  );

  const stationOptions = POLICY_STATION_OPTIONS[selectedPlan.key];
  const thresholdOptions = POLICY_THRESHOLD_OPTIONS[selectedPlan.key];
  const activeStationKey = stationOptions.some((option) => option.key === stationKey) ? stationKey : stationOptions[0].key;
  const activeThresholdValue = thresholdOptions.some((option) => option.value === thresholdValue)
    ? thresholdValue
    : thresholdOptions[0].value;
  const thresholdLabels = messages.policies.new.thresholds[
    selectedPlan.key as keyof typeof messages.policies.new.thresholds
  ] as Record<string, string>;
  const selectedStation = stationOptions.find((option) => option.key === activeStationKey) ?? stationOptions[0];
  const selectedThreshold =
    thresholdOptions.find((option) => option.value === activeThresholdValue) ?? thresholdOptions[0];
  const selectedPayoutTier =
    POLICY_PAYOUT_TIER_OPTIONS.find((option) => option.key === payoutTierKey) ?? POLICY_PAYOUT_TIER_OPTIONS[0];

  function updatePlan(nextPlanKey: string) {
    const nextPlan = POLICY_PLAN_OPTIONS.find((option) => option.key === nextPlanKey);
    if (!nextPlan) {
      return;
    }

    setPlanKey(nextPlan.key);
    setStationKey(POLICY_STATION_OPTIONS[nextPlan.key][0].key);
    setThresholdValue(POLICY_THRESHOLD_OPTIONS[nextPlan.key][0].value);
  }

  const handleRecaptchaVerify = useCallback((token: string) => {
    setRecaptchaToken(token);
  }, []);

  const handleRecaptchaExpire = useCallback(() => {
    setRecaptchaToken(null);
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!recaptchaToken) {
      setStatusMessage(messages.policies.new.errors.recaptchaRequired);
      setStep(4);
      return;
    }

    if (!masters) {
      setStatusMessage(messages.policies.new.errors.mastersLoadFailed);
      return;
    }

    const plan = masters.plans.find((option) => option.code === selectedPlan.key);
    const station = masters.stations.find((option) => option.code === selectedStation.key);
    const payoutTier = masters.payoutTiers.find((option) => option.code === selectedPayoutTier.key);

    if (!plan || !station || !payoutTier) {
      setStatusMessage(messages.policies.new.errors.mastersLoadFailed);
      return;
    }

    setSubmitting(true);
    setStatusMessage("");

    try {
      const response = await fetch("/api/v1/policies", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          plan_id: plan.id,
          station_id: station.id,
          payout_tier_id: payoutTier.id,
          threshold: activeThresholdValue,
          recaptcha_token: recaptchaToken,
        }),
      });

      const responseBody = await response.text();
      const parsedBody = responseBody ? (JSON.parse(responseBody) as { error?: string; policy?: { id?: number } }) : {};

      if (!response.ok || !parsedBody.policy?.id) {
        if (parsedBody.error === "duplicate_policy") {
          setStatusMessage(messages.policies.new.errors.duplicatePolicy);
        } else {
          setStatusMessage(messages.policies.new.errors.submitFailed);
        }

        setRecaptchaToken(null);
        setRecaptchaResetKey((value) => value + 1);
        return;
      }

      router.push("/mypage");
    } catch {
      setStatusMessage(messages.policies.new.errors.submitFailed);
      setRecaptchaToken(null);
      setRecaptchaResetKey((value) => value + 1);
    } finally {
      setSubmitting(false);
    }
  }

  const stepLabels = [
    messages.policies.new.steps.plan,
    messages.policies.new.steps.station,
    messages.policies.new.steps.threshold,
    messages.policies.new.steps.payoutTier,
    messages.policies.new.steps.confirm,
  ];

  return (
    <form className="wizard" onSubmit={handleSubmit}>
      <div className="wizard__intro">
        <p className="eyebrow">{messages.policies.new.eyebrow}</p>
        <h2>{messages.policies.new.title}</h2>
        <p className="wizard__description">{messages.policies.new.description}</p>
      </div>

      <ol className="wizard-stepper" aria-label={messages.policies.new.stepperLabel}>
        {stepLabels.map((label, index) => {
          const isActive = step === index;
          const isComplete = step > index;

          return (
            <li key={label}>
              <button
                type="button"
                className="wizard-stepper__button"
                data-active={isActive}
                data-complete={isComplete}
                onClick={() => setStep(index as WizardStep)}
              >
                <span className="wizard-stepper__index">{index + 1}</span>
                <span className="wizard-stepper__label">{label}</span>
              </button>
            </li>
          );
        })}
      </ol>

      <section className="wizard-stage" aria-live="polite">
        {step === 0 ? (
          <WizardChoiceGroup
            title={messages.policies.new.steps.plan}
            description={messages.policies.new.planHelp}
            options={POLICY_PLAN_OPTIONS.map((option) => ({
              key: option.key,
              id: option.key,
              label: messages.policies.new.plans[option.key],
              hint: messages.policies.new.planDescriptions[option.key],
            }))}
            selectedId={planKey}
            onSelect={(nextPlanKey) => updatePlan(String(nextPlanKey))}
          />
        ) : null}

        {step === 1 ? (
          <WizardChoiceGroup
            title={messages.policies.new.steps.station}
            description={messages.policies.new.stationHelp}
            options={stationOptions.map((option) => ({
              key: option.key,
              id: option.key,
              label: messages.policies.new.stations[option.key],
              hint: selectedPlan.key === "seismic"
                ? messages.policies.new.stationBadges.seismic
                : messages.policies.new.stationBadges.rainfall,
            }))}
            selectedId={activeStationKey}
            onSelect={(nextStationKey) => setStationKey(String(nextStationKey))}
          />
        ) : null}

        {step === 2 ? (
          <WizardChoiceGroup
            title={messages.policies.new.steps.threshold}
            description={messages.policies.new.thresholdHelp}
            options={thresholdOptions.map((option) => ({
              key: option.key,
              id: option.value,
              label: thresholdLabels[option.key],
              hint: selectedPlan.key === "seismic"
                ? messages.policies.new.thresholdBadges.seismic
                : messages.policies.new.thresholdBadges.rainfall,
            }))}
            selectedId={activeThresholdValue}
            onSelect={(nextThresholdValue) => setThresholdValue(String(nextThresholdValue))}
          />
        ) : null}

        {step === 3 ? (
          <WizardChoiceGroup
            title={messages.policies.new.steps.payoutTier}
            description={messages.policies.new.payoutHelp}
            options={POLICY_PAYOUT_TIER_OPTIONS.map((option) => ({
              key: option.key,
              id: option.key,
              label: messages.policies.new.payoutTiers[option.key],
              hint: messages.policies.new.payoutBadges[option.key],
            }))}
            selectedId={payoutTierKey}
            onSelect={(nextTierKey) => setPayoutTierKey(String(nextTierKey))}
          />
        ) : null}

        {step === 4 ? (
          <div className="wizard-review">
            <div className="wizard-review__summary">
              <h3>{messages.policies.new.reviewTitle}</h3>
              <dl className="wizard-review__list">
                <div>
                  <dt>{messages.policies.new.reviewLabels.plan}</dt>
                  <dd>{messages.policies.new.plans[selectedPlan.key]}</dd>
                </div>
                <div>
                  <dt>{messages.policies.new.reviewLabels.station}</dt>
                  <dd>{messages.policies.new.stations[selectedStation.key]}</dd>
                </div>
                <div>
                  <dt>{messages.policies.new.reviewLabels.threshold}</dt>
                  <dd>{thresholdLabels[selectedThreshold.key]}</dd>
                </div>
                <div>
                  <dt>{messages.policies.new.reviewLabels.payoutTier}</dt>
                  <dd>{messages.policies.new.payoutTiers[selectedPayoutTier.key]}</dd>
                </div>
              </dl>
            </div>

            {mastersError ? (
              <p className="status-message status-message--error">{messages.policies.new.errors.mastersLoadFailed}</p>
            ) : !masters ? (
              <p className="inline-note">{messages.policies.new.loadingMasters}</p>
            ) : null}

            <div className="wizard-recaptcha">
              <strong>{messages.policies.new.recaptchaLabel}</strong>
              <small>{messages.policies.new.recaptchaHint}</small>
              {RECAPTCHA_SITE_KEY ? (
                <RecaptchaWidget
                  key={recaptchaResetKey}
                  siteKey={RECAPTCHA_SITE_KEY}
                  onVerify={handleRecaptchaVerify}
                  onExpire={handleRecaptchaExpire}
                />
              ) : (
                <p className="status-message status-message--error">{messages.policies.new.errors.recaptchaUnavailable}</p>
              )}
            </div>

            <label className="wizard-field">
              <span>{messages.policies.new.ageGroupLabel}</span>
              <select value={ageGroupValue} onChange={(event) => setAgeGroupValue(event.target.value as PolicyAgeGroupValue)}>
                {POLICY_AGE_GROUP_OPTIONS.map((option) => (
                  <option key={option.key} value={option.value}>
                    {messages.policies.new.ageGroups[option.key]}
                  </option>
                ))}
              </select>
            </label>
          </div>
        ) : null}
      </section>

      <div className="wizard-actions">
        <button
          type="button"
          className="secondary-button"
          onClick={() => setStep((currentStep) => Math.max(0, currentStep - 1) as WizardStep)}
          disabled={step === 0}
        >
          {messages.policies.new.actions.back}
        </button>

        {step < 4 ? (
          <button
            type="button"
            className="primary-button"
            onClick={() => setStep((currentStep) => Math.min(4, currentStep + 1) as WizardStep)}
          >
            {messages.policies.new.actions.next}
          </button>
        ) : (
          <button
            type="submit"
            className="primary-button"
            disabled={submitting || !recaptchaToken || !masters}
          >
            {submitting ? messages.policies.new.actions.submitting : messages.policies.new.actions.submit}
          </button>
        )}
      </div>

      {statusMessage ? <p className="status-message status-message--error">{statusMessage}</p> : null}
    </form>
  );
}

function WizardChoiceGroup({
  title,
  description,
  options,
  selectedId,
  onSelect,
}: {
  title: string;
  description: string;
  options: Array<{
    key: string;
    id: string;
    label: string;
    hint: string;
  }>;
  selectedId: string;
  onSelect: (value: string) => void;
}) {
  return (
    <div className="wizard-choice-group">
      <div className="wizard-choice-group__heading">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>

      <div className="wizard-choice-grid" role="list">
        {options.map((option) => (
          <button
            key={option.key}
            type="button"
            className="wizard-choice"
            data-selected={selectedId === option.id}
            onClick={() => onSelect(option.id)}
          >
            <span className="wizard-choice__label">{option.label}</span>
            <span className="wizard-choice__hint">{option.hint}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
