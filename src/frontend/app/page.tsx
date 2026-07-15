"use client";

import Link from "next/link";
import { useLocale } from "@/components/LocaleContext";
import { PageSection } from "@/components/PageSection";

export default function Home() {
  const { messages } = useLocale();

  return (
    <PageSection title={messages.home.title} description={messages.home.description}>
      <div className="stack">
        <p className="eyebrow">{messages.home.eyebrow}</p>

        <div className="feature-grid">
          <article className="panel panel--quiet">
            <h2>{messages.home.featureA}</h2>
          </article>
          <article className="panel panel--quiet">
            <h2>{messages.home.featureB}</h2>
          </article>
          <article className="panel panel--quiet">
            <h2>{messages.home.featureC}</h2>
          </article>
        </div>

        <div className="action-row">
          <Link href="/login" className="primary-button">
            {messages.home.primaryAction}
          </Link>
          <span className="inline-note">{messages.home.secondaryAction}</span>
        </div>
      </div>
    </PageSection>
  );
}
