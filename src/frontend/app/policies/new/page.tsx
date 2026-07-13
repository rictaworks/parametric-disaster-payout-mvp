'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useSession } from 'next-auth/react';
import { WizardLayout } from '@/components/wizard/WizardLayout';

export default function NewPolicyPage() {
  const { status } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (status === 'unauthenticated') {
      router.replace('/login');
    }
  }, [router, status]);

  if (status !== 'authenticated') {
    return (
      <main className="mx-auto flex min-h-[calc(100vh-7rem)] max-w-5xl items-center justify-center px-4">
        <i className="fa-solid fa-spinner fa-spin text-2xl text-primary" aria-hidden="true" />
      </main>
    );
  }

  return <WizardLayout />;
}
