'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useSession } from 'next-auth/react';
import { fetchPolicies } from '@/lib/api';
import { useLocale, useT } from '@/lib/i18n';
import type { Policy } from '@/lib/types';

export default function DashboardPage() {
  const { status } = useSession();
  const router = useRouter();
  const t = useT();
  const { locale } = useLocale();
  const [policies, setPolicies] = useState<Policy[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (status === 'unauthenticated') {
      router.replace('/login');
      return;
    }

    if (status === 'authenticated') {
      fetchPolicies(locale)
        .then(setPolicies)
        .finally(() => setLoading(false));
    }
  }, [locale, router, status]);

  const moneyFormatter = useMemo(
    () => new Intl.NumberFormat(locale, { style: 'currency', currency: 'JPY', maximumFractionDigits: 0 }),
    [locale]
  );

  return (
    <main className="mx-auto max-w-5xl px-4 py-10">
      <div className="mb-8 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div>
          <h1 className="mb-2 text-3xl font-semibold">{t('dashboard_title')}</h1>
          <p className="text-sm text-muted">{t('dashboard_policies')}</p>
        </div>
        <Link className="action-button" href="/policies/new">
          <i className="fa-solid fa-file-signature" aria-hidden="true" />
          <span>{t('nav_apply')}</span>
        </Link>
      </div>

      <section className="surface-card p-6 shadow-xl">
        {loading ? (
          <div className="flex justify-center py-10">
            <i className="fa-solid fa-spinner fa-spin text-2xl text-primary" aria-hidden="true" />
          </div>
        ) : policies.length === 0 ? (
          <div className="py-6 text-sm text-muted">{t('dashboard_no_policies')}</div>
        ) : (
          <div className="grid gap-4">
            {policies.map((policy) => (
              <article key={policy.id} className="selection-card p-5">
                <div className="mb-3 flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
                  <div className="text-lg font-semibold">{policy.plan.label}</div>
                  <div className="text-sm text-primary">{t(`status_${policy.status}`)}</div>
                </div>
                <dl className="grid gap-2 text-sm md:grid-cols-2">
                  <div>
                    <dt className="text-muted">{t('confirm_station')}</dt>
                    <dd>{policy.station.label}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">{t('confirm_threshold')}</dt>
                    <dd>{policy.threshold}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">{t('confirm_tier')}</dt>
                    <dd>{moneyFormatter.format(policy.payout_tier.amount_jpy)}</dd>
                  </div>
                  <div>
                    <dt className="text-muted">{t('wizard_step5')}</dt>
                    <dd>{new Date(policy.waiting_until).toLocaleString(locale)}</dd>
                  </div>
                </dl>
              </article>
            ))}
          </div>
        )}
      </section>
    </main>
  );
}
