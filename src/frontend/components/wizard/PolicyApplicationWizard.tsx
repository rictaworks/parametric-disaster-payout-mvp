"use client";

import type { FormEvent } from "react";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useLocale } from "@/components/LocaleContext";
import {
  POLICY_AGE_GROUP_OPTIONS,
  POLICY_PAYOUT_TIER_OPTIONS,
  POLICY_PLAN_OPTIONS,
  POLICY_STATION_OPTIONS,
  POLICY_THRESHOLD_OPTIONS,
  POLICY_WIZARD_STORAGE_KEY,
  type PolicyAgeGroupValue,
  type PolicyApplicationRecord,
} from "./policyWizardData";

type WizardStep = 0 | 1 | 2 | 3 | 4;

export function PolicyApplicationWizard() {
  const { messages } = useLocale();
  const router = useRouter();

  const [step, setStep] = useState<WizardStep>(0);
  const [planId, setPlanId] = useState<number>(POLICY_PLAN_OPTIONS[0].id);
  const [stationId, setStationId] = useState<number>(POLICY_STATION_OPTIONS.seismic[0].id);
  const [thresholdValue, setThresholdValue] = useState<string>(POLICY_THRESHOLD_OPTIONS.seismic[0].value);
  const [payoutTierId, setPayoutTierId] = useState<number>(POLICY_PAYOUT_TIER_OPTIONS[0].id);
  const [ageGroupValue, setAgeGroupValue] = useState<PolicyAgeGroupValue>("");
  const [recaptchaChecked, setRecaptchaChecked] = useState(false);
  const [statusMessage, setStatusMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const selectedPlan = useMemo(
    () => POLICY_PLAN_OPTIONS.find((option) => option.id === planId) ?? POLICY_PLAN_OPTIONS[0],
    [planId]
  );

  const stationOptions = POLICY_STATION_OPTIONS[selectedPlan.key];
  const thresholdOptions = POLICY_THRESHOLD_OPTIONS[selectedPlan.key];
  const activeStationId = stationOptions.some((option) => option.id === stationId) ? stationId : stationOptions[0].id;
  const activeThresholdValue = thresholdOptions.some((option) => option.value === thresholdValue)
    ? thresholdValue
    : thresholdOptions[0].value;
  const thresholdLabels = messages.policies.new.thresholds[
    selectedPlan.key as keyof typeof messages.policies.new.thresholds
  ] as Record<string, string>;
  const selectedStation = stationOptions.find((option) => option.id === activeStationId) ?? stationOptions[0];
  const selectedThreshold =
    thresholdOptions.find((option) => option.value === activeThresholdValue) ?? thresholdOptions[0];
  const selectedPayoutTier =
    POLICY_PAYOUT_TIER_OPTIONS.find((option) => option.id === payoutTierId) ?? POLICY_PAYOUT_TIER_OPTIONS[0];
  const selectedAgeGroup = POLICY_AGE_GROUP_OPTIONS.find((option) => option.value === ageGroupValue);

  function updatePlan(nextPlanId: number | string) {
    const normalizedPlanId = Number(nextPlanId);
    const nextPlan = POLICY_PLAN_OPTIONS.find((option) => option.id === normalizedPlanId);
    if (!nextPlan) {
      return;
    }

    setPlanId(nextPlan.id);
    setStationId(POLICY_STATION_OPTIONS[nextPlan.key][0].id);
    setThresholdValue(POLICY_THRESHOLD_OPTIONS[nextPlan.key][0].value);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!recaptchaChecked) {
      setStatusMessage(messages.policies.new.errors.recaptchaRequired);
      setStep(4);
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
          plan_id: planId,
          station_id: activeStationId,
          payout_tier_id: payoutTierId,
          threshold: activeThresholdValue,
          recaptcha_token: "simulated-recaptcha-token",
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
        return;
      }

      const record: PolicyApplicationRecord = {
        policyId: parsedBody.policy.id,
        statusKey: "pending",
        statusLabel: messages.policies.new.statuses.pending,
        planId: selectedPlan.id,
        planLabel: messages.policies.new.plans[selectedPlan.key],
        stationId: selectedStation.id,
        stationLabel: messages.policies.new.stations[selectedStation.key],
        thresholdValue: selectedThreshold.value,
        thresholdLabel: thresholdLabels[selectedThreshold.key],
        payoutTierId: selectedPayoutTier.id,
        payoutTierLabel: messages.policies.new.payoutTiers[selectedPayoutTier.key],
        ageGroupValue,
        ageGroupLabel: selectedAgeGroup ? messages.policies.new.ageGroups[selectedAgeGroup.key] : messages.policies.new.ageGroups.unspecified,
        submittedAt: new Date().toISOString(),
      };

      window.localStorage.setItem(POLICY_WIZARD_STORAGE_KEY, JSON.stringify(record));
      router.push("/mypage");
    } catch {
      setStatusMessage(messages.policies.new.errors.submitFailed);
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
              id: option.id,
              label: messages.policies.new.plans[option.key],
              hint: messages.policies.new.planDescriptions[option.key],
            }))}
            selectedId={planId}
            onSelect={(nextPlanId) => updatePlan(nextPlanId)}
          />
        ) : null}

        {step === 1 ? (
          <WizardChoiceGroup
            title={messages.policies.new.steps.station}
            description={messages.policies.new.stationHelp}
            options={stationOptions.map((option) => ({
              key: option.key,
              id: option.id,
              label: messages.policies.new.stations[option.key],
              hint: selectedPlan.key === "seismic"
                ? messages.policies.new.stationBadges.seismic
                : messages.policies.new.stationBadges.rainfall,
            }))}
            selectedId={activeStationId}
            onSelect={(nextStationId) => setStationId(Number(nextStationId))}
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
              id: option.id,
              label: messages.policies.new.payoutTiers[option.key],
              hint: messages.policies.new.payoutBadges[option.key],
            }))}
            selectedId={payoutTierId}
            onSelect={(nextTierId) => setPayoutTierId(Number(nextTierId))}
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

            <label className="wizard-check">
              <input
                type="checkbox"
                checked={recaptchaChecked}
                onChange={(event) => setRecaptchaChecked(event.target.checked)}
              />
              <span>
                <strong>{messages.policies.new.recaptchaLabel}</strong>
                <small>{messages.policies.new.recaptchaHint}</small>
              </span>
            </label>

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
            disabled={submitting || !recaptchaChecked}
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
    id: number | string;
    label: string;
    hint: string;
  }>;
  selectedId: number | string;
  onSelect: (value: number | string) => void;
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
