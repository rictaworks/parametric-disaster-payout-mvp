"use client";

import Link from "next/link";
import { useLocale } from "@/components/LocaleContext";

const CONTACT = {
  name: "Ricta Works",
  address: "〒190-0022 東京都立川市錦町1丁目4-20 TSCビル5階",
  phone: "070-5148-0380",
  email: "info@rictaworks.jp",
  web: "https://rictaworks.jp",
  x: "@rictaworks",
  xUrl: "https://x.com/rictaworks",
  github: "github.com/rictaworks",
  githubUrl: "https://github.com/rictaworks",
};

export default function LegalPage() {
  const { messages } = useLocale();
  const { legal } = messages;

  return (
    <section className="page-section panel legal-page">
      <div className="page-section__header">
        <Link href="/" className="legal-page__back">
          {legal.backLink}
        </Link>
        <h1>{legal.pageTitle}</h1>
      </div>

      <div className="stack">
        <section className="legal-section">
          <h2>{legal.termsHeading}</h2>
          <ul className="legal-list">
            {legal.terms.map((item, index) => (
              <li key={index}>{item}</li>
            ))}
          </ul>
        </section>

        <section className="legal-section">
          <h2>{legal.disclaimerHeading}</h2>
          <ul className="legal-list">
            {legal.disclaimer.map((item, index) => (
              <li key={index}>{item}</li>
            ))}
          </ul>
        </section>

        <section className="legal-section">
          <h2>{legal.contactHeading}</h2>
          <dl className="legal-contact">
            <div>
              <dt>{legal.contactLabels.name}</dt>
              <dd>{CONTACT.name}</dd>
            </div>
            <div>
              <dt>{legal.contactLabels.address}</dt>
              <dd>{CONTACT.address}</dd>
            </div>
            <div>
              <dt>{legal.contactLabels.phone}</dt>
              <dd>{CONTACT.phone}</dd>
            </div>
            <div>
              <dt>{legal.contactLabels.email}</dt>
              <dd>{CONTACT.email}</dd>
            </div>
            <div>
              <dt>{legal.contactLabels.web}</dt>
              <dd>
                <a href={CONTACT.web} target="_blank" rel="noopener noreferrer">
                  {CONTACT.web}
                </a>
              </dd>
            </div>
            <div>
              <dt>{legal.contactLabels.x}</dt>
              <dd>
                <a href={CONTACT.xUrl} target="_blank" rel="noopener noreferrer">
                  {CONTACT.x}
                </a>
              </dd>
            </div>
            <div>
              <dt>{legal.contactLabels.github}</dt>
              <dd>
                <a href={CONTACT.githubUrl} target="_blank" rel="noopener noreferrer">
                  {CONTACT.github}
                </a>
              </dd>
            </div>
          </dl>
        </section>
      </div>
    </section>
  );
}
