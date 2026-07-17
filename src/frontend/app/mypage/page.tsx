"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { PageSection } from "@/components/PageSection";
import { useLocale } from "@/components/LocaleContext";
import { POLICY_PLAN_OPTIONS, findThresholdOption } from "@/components/wizard/policyWizardData";
import type { Messages } from "@/lib/i18n";

type FetchedPolicy = {
  id: number;
  plan_code: string;
  station_code: string | null;
  payout_tier_code: string;
  policy_status_code: string;
  threshold: string;
  waiting_until: string | null;
  expires_at: string | null;
  terminated_at: string | null;
};

type FetchedPayout = {
  id: number;
  policy_id: number;
  policy_plan_code: string;
  policy_station_code: string | null;
  policy_status_code: string;
  policy_threshold: string;
  payout_tier_code: string;
  payout_tier_amount_yen: number;
  payout_status_code: string;
  survey_response_submitted: boolean;
  decided_at: string | null;
  created_at: string;
};

type FetchedNotification = {
  id: number;
  kind: string;
  message: string;
  policy_id: number | null;
  payout_id: number | null;
  delivered_at: string | null;
  read_at: string | null;
  created_at: string;
};

type PageState =
  | { status: "loading" }
  | { status: "unauthenticated" }
  | { status: "error" }
  | {
      status: "ready";
      policies: FetchedPolicy[];
      payouts: FetchedPayout[];
      notifications: FetchedNotification[];
    };

function formatDateTime(value: string | null) {
  if (!value) {
    return "-";
  }

  return new Intl.DateTimeFormat("ja-JP", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(value));
}

function formatCountdown(waitingUntil: string | null, messages: Messages) {
  if (!waitingUntil) {
    return "-";
  }

  const diff = new Date(waitingUntil).getTime() - Date.now();
  if (diff <= 0) {
    return messages.mypage.countdown.elapsed;
  }

  const totalMinutes = Math.ceil(diff / 60_000);
  const days = Math.floor(totalMinutes / 1_440);
  const hours = Math.floor((totalMinutes % 1_440) / 60);
  const minutes = totalMinutes % 60;

  const parts = [] as string[];
  if (days > 0) {
    parts.push(`${days}日`);
  }
  if (hours > 0) {
    parts.push(`${hours}時間`);
  }
  if (parts.length === 0) {
    parts.push(`${minutes}分`);
  }

  return `${messages.mypage.countdown.remainingPrefix}${parts.join(" ")}`;
}

export default function MyPage() {
  const { messages } = useLocale();
  const [state, setState] = useState<PageState>({ status: "loading" });
  const [surveyDraft, setSurveyDraft] = useState(messages.mypage.survey.defaultFeedback);
  const [satisfaction, setSatisfaction] = useState<number>(5);
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [submittingSurvey, setSubmittingSurvey] = useState(false);

  useEffect(() => {
    let cancelled = false;

    Promise.all([
      fetch("/api/v1/policies"),
      fetch("/api/v1/payouts"),
      fetch("/api/v1/notifications"),
    ])
      .then(async ([policiesResponse, payoutsResponse, notificationsResponse]) => {
        if (cancelled) {
          return;
        }

        if ([policiesResponse, payoutsResponse, notificationsResponse].some((response) => response.status === 401)) {
          setState({ status: "unauthenticated" });
          return;
        }

        if ([policiesResponse, payoutsResponse, notificationsResponse].some((response) => !response.ok)) {
          setState({ status: "error" });
          return;
        }

        const [policiesBody, payoutsBody, notificationsBody] = await Promise.all([
          policiesResponse.json() as Promise<{ policies: FetchedPolicy[] }>,
          payoutsResponse.json() as Promise<{ payouts: FetchedPayout[] }>,
          notificationsResponse.json() as Promise<{ notifications: FetchedNotification[] }>,
        ]);

        setState({
          status: "ready",
          policies: policiesBody.policies,
          payouts: payoutsBody.payouts,
          notifications: notificationsBody.notifications,
        });
      })
      .catch(() => {
        if (!cancelled) {
          setState({ status: "error" });
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  function planLabel(code: string) {
    const plans = messages.policies.new.plans as Record<string, string>;
    return plans[code] ?? code;
  }

  function stationLabel(code: string | null) {
    if (!code) {
      return "-";
    }

    const stations = messages.policies.new.stations as Record<string, string>;
    return stations[code] ?? code;
  }

  function payoutTierLabel(code: string) {
    const payoutTiers = messages.policies.new.payoutTiers as Record<string, string>;
    return payoutTiers[code] ?? code;
  }

  function statusLabel(code: string) {
    const statuses = messages.policies.new.statuses as Record<string, string>;
    return statuses[code] ?? statuses.unknown ?? code;
  }

  function thresholdLabel(planCode: string, value: string) {
    const plan = POLICY_PLAN_OPTIONS.find((option) => option.key === planCode);
    if (!plan) {
      return value;
    }

    const thresholdOption = findThresholdOption(plan.key, value);
    if (!thresholdOption) {
      return value;
    }

    const labels = messages.policies.new.thresholds[plan.key] as Record<string, string>;
    return labels[thresholdOption.key] ?? value;
  }

  function updatePolicy(updatedPolicy: FetchedPolicy) {
    setState((current) => {
      if (current.status !== "ready") {
        return current;
      }

      return {
        ...current,
        policies: current.policies.map((policy) => (policy.id === updatedPolicy.id ? updatedPolicy : policy)),
      };
    });
  }

  function updatePayout(updatedPayout: FetchedPayout) {
    setState((current) => {
      if (current.status !== "ready") {
        return current;
      }

      return {
        ...current,
        payouts: current.payouts.map((payout) => (payout.id === updatedPayout.id ? updatedPayout : payout)),
      };
    });
  }

  async function patchPolicyAction(path: string) {
    setActionError(null);
    setActionMessage(null);

    const response = await fetch(path, { method: "PATCH" });

    if (response.status === 401) {
      setState({ status: "unauthenticated" });
      return;
    }

    if (response.status === 403) {
      setActionError(messages.mypage.status.forbidden);
      return;
    }

    if (!response.ok) {
      setActionError(messages.mypage.status.updateFailed);
      return;
    }

    const body = (await response.json()) as { policy: FetchedPolicy };
    updatePolicy(body.policy);
    setActionMessage(messages.mypage.status.updated);
  }

  async function handleSurveySubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const surveyTarget =
      state.status === "ready"
        ? state.payouts.find((payout) => payout.payout_status_code === "completed_simulated" && !payout.survey_response_submitted)
        : null;

    if (!surveyTarget) {
      return;
    }

    setSubmittingSurvey(true);
    setActionError(null);
    setActionMessage(null);

    try {
      const response = await fetch("/api/v1/survey_responses", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          payout_id: surveyTarget.id,
          response_data: {
            satisfaction: satisfaction,
            feedback: surveyDraft,
          },
        }),
      });

      if (response.status === 401) {
        setState({ status: "unauthenticated" });
        return;
      }

      if (response.status === 403) {
        setActionError(messages.mypage.survey.forbidden);
        return;
      }

      if (!response.ok) {
        setActionError(messages.mypage.survey.submitFailed);
        return;
      }

      const body = (await response.json()) as { survey_response: { payout_id: number } };
      updatePayout({
        ...surveyTarget,
        survey_response_submitted: true,
      });
      setSurveyDraft(messages.mypage.survey.defaultFeedback);
      setSatisfaction(5);
      setActionMessage(`${messages.mypage.survey.savedPrefix}${body.survey_response.payout_id}${messages.mypage.survey.savedSuffix}`);
    } finally {
      setSubmittingSurvey(false);
    }
  }

  const surveyTarget =
    state.status === "ready"
      ? state.payouts.find((payout) => payout.payout_status_code === "completed_simulated" && !payout.survey_response_submitted)
      : null;

  return (
    <PageSection title={messages.mypage.title} description={messages.mypage.description}>
      <div className="stack">
        {state.status === "loading" ? <p className="inline-note">{messages.mypage.loading}</p> : null}

        {state.status === "unauthenticated" ? (
          <article className="panel panel--quiet">
            <p>{messages.mypage.unauthenticated}</p>
          </article>
        ) : null}

        {state.status === "error" ? (
          <article className="panel panel--quiet">
            <p className="status-message status-message--error">{messages.mypage.loadFailed}</p>
          </article>
        ) : null}

        {actionError ? (
          <article className="panel panel--quiet">
            <p className="status-message status-message--error">{actionError}</p>
          </article>
        ) : null}

        {actionMessage ? (
          <article className="panel panel--quiet">
            <p>{actionMessage}</p>
          </article>
        ) : null}

        {state.status === "ready" ? (
          <>
            {surveyTarget ? (
              <article className="panel panel--quiet stack">
                <p className="eyebrow">{messages.mypage.survey.requestTitle}</p>
                <h2>{messages.mypage.survey.requestDescription}</h2>
                <p>{`${messages.mypage.survey.targetPayoutPrefix}${surveyTarget.id} / ${payoutTierLabel(surveyTarget.payout_tier_code)}`}</p>

                <form className="mypage-form" onSubmit={handleSurveySubmit}>
                  <div className="field" style={{ marginBottom: "1rem" }}>
                    <span style={{ display: "block", marginBottom: "0.5rem", fontWeight: "bold" }}>
                      {messages.mypage.survey.satisfactionLabel}
                    </span>
                    <div style={{ display: "flex", gap: "1.5rem", alignItems: "center" }}>
                      {[1, 2, 3, 4, 5].map((val) => (
                        <label key={val} style={{ display: "flex", alignItems: "center", gap: "0.25rem", cursor: "pointer" }}>
                          <input
                            type="radio"
                            name="satisfaction"
                            value={val}
                            checked={satisfaction === val}
                            onChange={() => setSatisfaction(val)}
                          />
                          <span style={{ fontSize: "1rem" }}>{val}</span>
                        </label>
                      ))}
                    </div>
                  </div>

                  <label>
                    <span>{messages.mypage.survey.feedbackLabel}</span>
                    <textarea value={surveyDraft} onChange={(event) => setSurveyDraft(event.target.value)} rows={4} />
                  </label>
                  <div className="action-row">
                    <button className="primary-button" type="submit" disabled={submittingSurvey}>
                      {submittingSurvey ? messages.mypage.survey.submitting : messages.mypage.survey.submit}
                    </button>
                  </div>
                </form>
              </article>
            ) : null}

            <article className="panel panel--quiet stack">
              <p className="eyebrow">{messages.mypage.policiesHeading}</p>
              {state.policies.length === 0 ? (
                <p>{messages.mypage.emptyState}</p>
              ) : (
                state.policies.map((policy) => (
                  <article key={policy.id} className="mypage-card">
                    <div className="mypage-card__header">
                      <strong className="mypage-card__status">{statusLabel(policy.policy_status_code)}</strong>
                      <span>{`${messages.mypage.countdownLabel}${formatCountdown(policy.waiting_until, messages)}`}</span>
                    </div>

                    <dl className="mypage-card__list">
                      <div>
                        <dt>{messages.mypage.labels.plan}</dt>
                        <dd>{planLabel(policy.plan_code)}</dd>
                      </div>
                      <div>
                        <dt>{messages.mypage.labels.station}</dt>
                        <dd>{stationLabel(policy.station_code)}</dd>
                      </div>
                      <div>
                        <dt>{messages.mypage.labels.threshold}</dt>
                        <dd>{thresholdLabel(policy.plan_code, policy.threshold)}</dd>
                      </div>
                      <div>
                        <dt>{messages.mypage.labels.payoutTier}</dt>
                        <dd>{payoutTierLabel(policy.payout_tier_code)}</dd>
                      </div>
                      <div>
                        <dt>{messages.mypage.terminatedAt}</dt>
                        <dd>{formatDateTime(policy.terminated_at)}</dd>
                      </div>
                    </dl>

                    <div className="action-row">
                      {policy.policy_status_code === "pending" ? (
                        <button
                          className="primary-button"
                          type="button"
                          onClick={() => patchPolicyAction(`/api/v1/policies/${policy.id}/force_waiting_period_elapsed`)}
                        >
                          {messages.mypage.actions.forceWaitingPeriod}
                        </button>
                      ) : null}

                      {policy.policy_status_code !== "cancelled" && policy.policy_status_code !== "expired" ? (
                        <button className="primary-button" type="button" onClick={() => patchPolicyAction(`/api/v1/policies/${policy.id}/cancel`)}>
                          {messages.mypage.actions.cancel}
                        </button>
                      ) : null}
                    </div>
                  </article>
                ))
              )}
            </article>

            <article className="panel panel--quiet">
              <p className="eyebrow">{messages.mypage.notificationsHeading}</p>
              {state.notifications.length === 0 ? (
                <p>{messages.mypage.emptyNotifications}</p>
              ) : (
                <table className="mypage-table">
                  <thead>
                    <tr>
                      <th>{messages.mypage.notificationTable.kind}</th>
                      <th>{messages.mypage.notificationTable.message}</th>
                      <th>{messages.mypage.notificationTable.receivedAt}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {state.notifications.map((notification) => (
                      <tr key={notification.id}>
                        <td>{notification.kind}</td>
                        <td>{notification.message}</td>
                        <td>{formatDateTime(notification.created_at)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </article>

            <article className="panel panel--quiet">
              <p className="eyebrow">{messages.mypage.payoutsHeading}</p>
              {state.payouts.length === 0 ? (
                <p>{messages.mypage.emptyPayouts}</p>
              ) : (
                <table className="mypage-table">
                  <thead>
                    <tr>
                      <th>{messages.mypage.payoutTable.date}</th>
                      <th>{messages.mypage.payoutTable.policy}</th>
                      <th>{messages.mypage.payoutTable.tier}</th>
                      <th>{messages.mypage.payoutTable.status}</th>
                      <th>{messages.mypage.payoutTable.survey}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {state.payouts.map((payout) => (
                      <tr key={payout.id}>
                        <td>{formatDateTime(payout.decided_at ?? payout.created_at)}</td>
                        <td>{`${planLabel(payout.policy_plan_code)} / ${stationLabel(payout.policy_station_code)}`}</td>
                        <td>{`${payoutTierLabel(payout.payout_tier_code)} (${payout.payout_tier_amount_yen.toLocaleString("ja-JP")}円)`}</td>
                        <td>{statusLabel(payout.policy_status_code)}</td>
                        <td>{payout.survey_response_submitted ? messages.mypage.surveyStatus.submitted : messages.mypage.surveyStatus.pending}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </article>
          </>
        ) : null}

        <div className="action-row">
          <Link href="/policies/new" className="primary-button">
            {messages.mypage.primaryAction}
          </Link>
        </div>
      </div>
    </PageSection>
  );
}
