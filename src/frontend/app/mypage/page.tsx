"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { PageSection } from "@/components/PageSection";
import { useLocale } from "@/components/LocaleContext";
import { POLICY_PLAN_OPTIONS, POLICY_THRESHOLD_OPTIONS } from "@/components/wizard/policyWizardData";

type FetchedPolicy = {
  id: number;
  plan_code: string;
  station_code: string | null;
  payout_tier_code: string;
  policy_status_code: string;
  threshold: string;
};

type PageState =
  | { status: "loading" }
  | { status: "unauthenticated" }
  | { status: "error" }
  | { status: "ready"; policies: FetchedPolicy[] };

export default function MyPage() {
  const { messages } = useLocale();
  const [state, setState] = useState<PageState>({ status: "loading" });

  useEffect(() => {
    let cancelled = false;

    fetch("/api/v1/policies")
      .then(async (response) => {
        if (cancelled) {
          return;
        }

        if (response.status === 401) {
          setState({ status: "unauthenticated" });
          return;
        }

        if (!response.ok) {
          setState({ status: "error" });
          return;
        }

        const body = (await response.json()) as { policies: FetchedPolicy[] };
        setState({ status: "ready", policies: body.policies });
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

    const thresholdOption = POLICY_THRESHOLD_OPTIONS[plan.key].find((option) => option.value === value);
    if (!thresholdOption) {
      return value;
    }

    const labels = messages.policies.new.thresholds[plan.key] as Record<string, string>;
    return labels[thresholdOption.key] ?? value;
  }

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

        {state.status === "ready" ? (
          state.policies.length === 0 ? (
            <article className="panel panel--quiet">
              <p>{messages.mypage.emptyState}</p>
            </article>
          ) : (
            <>
              <p className="eyebrow">{messages.mypage.applicationsHeading}</p>

              {state.policies.map((policy) => (
                <article key={policy.id} className="panel panel--quiet mypage-card">
                  <div className="mypage-card__header">
                    <strong className="mypage-card__status">{statusLabel(policy.policy_status_code)}</strong>
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
                  </dl>

                  <p className="mypage-card__footnote">{messages.mypage.waitingExplanation}</p>
                </article>
              ))}
            </>
          )
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
