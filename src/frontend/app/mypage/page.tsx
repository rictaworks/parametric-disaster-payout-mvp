"use client";

import { useState } from "react";
import Link from "next/link";
import { PageSection } from "@/components/PageSection";
import { useLocale } from "@/components/LocaleContext";
import { POLICY_WIZARD_STORAGE_KEY, type PolicyApplicationRecord } from "@/components/wizard/policyWizardData";

export default function MyPage() {
  const { messages } = useLocale();
  const [application] = useState<PolicyApplicationRecord | null>(() => {
    if (typeof window === "undefined") {
      return null;
    }

    const raw = window.localStorage.getItem(POLICY_WIZARD_STORAGE_KEY);
    if (!raw) {
      return null;
    }

    try {
      return JSON.parse(raw) as PolicyApplicationRecord;
    } catch {
      return null;
    }
  });

  return (
    <PageSection title={messages.mypage.title} description={messages.mypage.description}>
      <div className="stack">
        {application ? (
          <article className="panel panel--quiet mypage-card">
            <div className="mypage-card__header">
              <p className="eyebrow">{messages.mypage.latestApplication}</p>
              <strong className="mypage-card__status">{application.statusLabel}</strong>
            </div>

            <dl className="mypage-card__list">
              <div>
                <dt>{messages.mypage.labels.plan}</dt>
                <dd>{application.planLabel}</dd>
              </div>
              <div>
                <dt>{messages.mypage.labels.station}</dt>
                <dd>{application.stationLabel}</dd>
              </div>
              <div>
                <dt>{messages.mypage.labels.threshold}</dt>
                <dd>{application.thresholdLabel}</dd>
              </div>
              <div>
                <dt>{messages.mypage.labels.payoutTier}</dt>
                <dd>{application.payoutTierLabel}</dd>
              </div>
              <div>
                <dt>{messages.mypage.labels.ageGroup}</dt>
                <dd>{application.ageGroupLabel}</dd>
              </div>
            </dl>

            <p className="mypage-card__footnote">{messages.mypage.waitingExplanation}</p>
          </article>
        ) : (
          <article className="panel panel--quiet">
            <p>{messages.mypage.emptyState}</p>
          </article>
        )}

        <div className="action-row">
          <Link href="/policies/new" className="primary-button">
            {messages.mypage.primaryAction}
          </Link>
        </div>
      </div>
    </PageSection>
  );
}
