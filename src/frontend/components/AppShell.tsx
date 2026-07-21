"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { DemoBanner } from "@/components/DemoBanner";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { LocaleProvider, useLocale } from "@/components/LocaleContext";

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <LocaleProvider>
      <DemoBanner />
      <div className="app-shell">
        <header className="app-header">
          <AppBrand />

          <div className="app-header__actions">
            <AppNavigation />
            <LanguageSwitcher />
          </div>
        </header>

        <main className="app-content">{children}</main>

        <AppFooter />
      </div>

      <ConsultButton />
    </LocaleProvider>
  );
}

function AppBrand() {
  const { messages } = useLocale();

  return (
    <Link href="/" className="brand-mark" aria-label={messages.app.title}>
      <span className="brand-mark__name">{messages.app.title}</span>
      <span className="brand-mark__tagline">{messages.app.tagline}</span>
    </Link>
  );
}

function AppNavigation() {
  const { messages } = useLocale();

  return (
    <nav className="app-nav" aria-label={messages.navigation.label}>
      <Link href="/" className="app-nav__link">
        {messages.navigation.home}
      </Link>
      <Link href="/policies/new" className="app-nav__link">
        {messages.navigation.policies}
      </Link>
      <Link href="/mypage" className="app-nav__link">
        {messages.navigation.mypage}
      </Link>
      <Link href="/login" className="app-nav__link">
        {messages.navigation.login}
      </Link>
      <a
        href="https://rictaworks.jp/#demos"
        className="app-nav__link app-nav__link--external"
      >
        {messages.navigation.demoList}
      </a>
    </nav>
  );
}

function AppFooter() {
  const { messages } = useLocale();

  return (
    <footer className="app-footer">
      <Link href="/legal" className="app-footer__link">
        {messages.footer.legal}
      </Link>
      <span className="app-footer__copyright">{messages.footer.copyright}</span>
    </footer>
  );
}

function ConsultButton() {
  const { messages } = useLocale();

  return (
    <a
      href="https://rictaworks.jp/"
      target="_blank"
      rel="noopener noreferrer"
      className="consult-button"
    >
      {messages.consult.cta}
    </a>
  );
}
