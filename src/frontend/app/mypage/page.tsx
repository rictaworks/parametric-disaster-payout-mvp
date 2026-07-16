"use client";

import { FormEvent, useEffect, useState } from "react";
import Link from "next/link";
import { PageSection } from "@/components/PageSection";
import { useLocale } from "@/components/LocaleContext";
import { POLICY_PLAN_OPTIONS, findThresholdOption } from "@/components/wizard/policyWizardData";

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

function formatCountdown(waitingUntil: string | null) {
  if (!waitingUntil) {
    return "-";
  }

  const diff = new Date(waitingUntil).getTime() - Date.now();
  if (diff <= 0) {
    return "免責明け済み";
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

  return `あと ${parts.join(" ")}`;
}

export default function MyPage() {
  const { messages } = useLocale();
  const [state, setState] = useState<PageState>({ status: "loading" });
  const [surveyDraft, setSurveyDraft] = useState("今回の模擬支払体験の感想をお聞かせください。");
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
      setActionError("この契約は操作できません。");
      return;
    }

    if (!response.ok) {
      setActionError("契約の更新に失敗しました。");
      return;
    }

    const body = (await response.json()) as { policy: FetchedPolicy };
    updatePolicy(body.policy);
    setActionMessage("契約を更新しました。");
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
            feedback: surveyDraft,
          },
        }),
      });

      if (response.status === 401) {
        setState({ status: "unauthenticated" });
        return;
      }

      if (response.status === 403) {
        setActionError("アンケートを送信できません。");
        return;
      }

      if (!response.ok) {
        setActionError("アンケートの送信に失敗しました。");
        return;
      }

      const body = (await response.json()) as { survey_response: { payout_id: number } };
      updatePayout({
        ...surveyTarget,
        survey_response_submitted: true,
      });
      setSurveyDraft("今回の模擬支払体験の感想をお聞かせください。");
      setActionMessage(`アンケートを保存しました。（支払ID: ${body.survey_response.payout_id}）`);
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
                <p className="eyebrow">アンケート依頼</p>
                <h2>支払完了（模擬）後の回答にご協力ください。</h2>
                <p>{`対象支払ID: ${surveyTarget.id} / ${payoutTierLabel(surveyTarget.payout_tier_code)}`}</p>

                <form className="mypage-form" onSubmit={handleSurveySubmit}>
                  <label>
                    <span>回答内容</span>
                    <textarea value={surveyDraft} onChange={(event) => setSurveyDraft(event.target.value)} rows={4} />
                  </label>
                  <div className="action-row">
                    <button className="primary-button" type="submit" disabled={submittingSurvey}>
                      {submittingSurvey ? "送信中" : "アンケートを送信"}
                    </button>
                  </div>
                </form>
              </article>
            ) : null}

            <article className="panel panel--quiet stack">
              <p className="eyebrow">契約一覧</p>
              {state.policies.length === 0 ? (
                <p>{messages.mypage.emptyState}</p>
              ) : (
                state.policies.map((policy) => (
                  <article key={policy.id} className="mypage-card">
                    <div className="mypage-card__header">
                      <strong className="mypage-card__status">{statusLabel(policy.policy_status_code)}</strong>
                      <span>{`免責明けまで: ${formatCountdown(policy.waiting_until)}`}</span>
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
                        <dt>解約日時</dt>
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
                          【プロトタイプ操作】免責期間を即時経過
                        </button>
                      ) : null}

                      {policy.policy_status_code !== "cancelled" && policy.policy_status_code !== "expired" ? (
                        <button className="primary-button" type="button" onClick={() => patchPolicyAction(`/api/v1/policies/${policy.id}/cancel`)}>
                          解約
                        </button>
                      ) : null}
                    </div>
                  </article>
                ))
              )}
            </article>

            <article className="panel panel--quiet">
              <p className="eyebrow">通知一覧</p>
              {state.notifications.length === 0 ? (
                <p>通知はまだありません。</p>
              ) : (
                <table className="mypage-table">
                  <thead>
                    <tr>
                      <th>種別</th>
                      <th>本文</th>
                      <th>受信日時</th>
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
              <p className="eyebrow">支払履歴</p>
              {state.payouts.length === 0 ? (
                <p>支払履歴はまだありません。</p>
              ) : (
                <table className="mypage-table">
                  <thead>
                    <tr>
                      <th>支払日</th>
                      <th>契約</th>
                      <th>支払額区分</th>
                      <th>状態</th>
                      <th>アンケート</th>
                    </tr>
                  </thead>
                  <tbody>
                    {state.payouts.map((payout) => (
                      <tr key={payout.id}>
                        <td>{formatDateTime(payout.decided_at ?? payout.created_at)}</td>
                        <td>{`${planLabel(payout.policy_plan_code)} / ${stationLabel(payout.policy_station_code)}`}</td>
                        <td>{`${payoutTierLabel(payout.payout_tier_code)} (${payout.payout_tier_amount_yen.toLocaleString("ja-JP")}円)`}</td>
                        <td>{statusLabel(payout.policy_status_code)}</td>
                        <td>{payout.survey_response_submitted ? "回答済み" : "未回答"}</td>
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
