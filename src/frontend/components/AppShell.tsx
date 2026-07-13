'use client';

import type { ReactNode } from 'react';
import Link from 'next/link';
import { signOut, useSession } from 'next-auth/react';
import { DemoBanner } from '@/components/DemoBanner';
import { LocaleSwitcher } from '@/components/LocaleSwitcher';
import { useT } from '@/lib/i18n';

export function AppShell({ children }: { children: ReactNode }) {
  const t = useT();
  const { status } = useSession();

  return (
    <div className="app-shell">
      <DemoBanner />
      <header className="border-b border-border/80 bg-surface/90">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-4 py-4 md:flex-row md:items-center md:justify-between">
          <nav className="flex flex-wrap items-center gap-3 text-sm">
            <Link className="action-button secondary-button" href="/login">
              <i className="fa-solid fa-right-to-bracket" aria-hidden="true" />
              <span>{t('nav_login')}</span>
            </Link>
            <Link className="action-button secondary-button" href="/dashboard">
              <i className="fa-solid fa-table-list" aria-hidden="true" />
              <span>{t('nav_dashboard')}</span>
            </Link>
            <Link className="action-button secondary-button" href="/policies/new">
              <i className="fa-solid fa-file-circle-plus" aria-hidden="true" />
              <span>{t('nav_apply')}</span>
            </Link>
            {status === 'authenticated' ? (
              <button type="button" className="action-button secondary-button" onClick={() => signOut({ callbackUrl: '/login' })}>
                <i className="fa-solid fa-arrow-right-from-bracket" aria-hidden="true" />
                <span>{t('nav_logout')}</span>
              </button>
            ) : null}
          </nav>
          <LocaleSwitcher />
        </div>
      </header>
      {children}
    </div>
  );
}
