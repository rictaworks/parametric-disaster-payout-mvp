'use client';

import { useEffect } from 'react';
import { signIn, useSession } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { useT } from '@/lib/i18n';

export default function LoginPage() {
  const { status } = useSession();
  const router = useRouter();
  const t = useT();

  useEffect(() => {
    if (status === 'authenticated') {
      router.replace('/dashboard');
    }
  }, [router, status]);

  return (
    <main className="mx-auto flex min-h-[calc(100vh-7rem)] max-w-3xl items-center justify-center px-4 py-10">
      <section className="surface-card w-full max-w-xl p-8 shadow-2xl">
        <div className="mb-6 flex items-center gap-3 text-2xl font-semibold">
          <i className="fa-solid fa-shield-halved text-primary" aria-hidden="true" />
          <span>{t('nav_login')}</span>
        </div>
        <div className="mb-6 text-sm text-muted">
          {t('wizard_title')}
        </div>
        <button
          type="button"
          className="action-button w-full"
          onClick={() => signIn('google', { callbackUrl: '/dashboard' })}
        >
          <i className="fa-brands fa-google" aria-hidden="true" />
          <span>{t('btn_login_google')}</span>
        </button>
      </section>
    </main>
  );
}
