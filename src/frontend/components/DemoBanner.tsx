'use client';

import { useT } from '@/lib/i18n';

export function DemoBanner() {
  const t = useT();

  return (
    <div className="border-b border-warning/60 bg-warning/10 px-4 py-3 text-center text-sm text-warning">
      <i className="fa-solid fa-triangle-exclamation mr-2" aria-hidden="true" />
      <span>{t('demo_banner')}</span>
    </div>
  );
}
