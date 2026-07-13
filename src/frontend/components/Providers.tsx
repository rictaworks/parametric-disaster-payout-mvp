'use client';

import type { ReactNode } from 'react';
import { SessionProvider } from 'next-auth/react';
import { LocaleProvider } from '@/lib/i18n';

export function Providers({ children }: { children: ReactNode }) {
  return (
    <SessionProvider>
      <LocaleProvider>{children}</LocaleProvider>
    </SessionProvider>
  );
}
