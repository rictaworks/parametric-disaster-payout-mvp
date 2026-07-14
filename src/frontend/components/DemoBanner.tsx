"use client";

import { useLocale } from "@/components/LocaleContext";

export function DemoBanner() {
  const { messages } = useLocale();

  return (
    <div className="demo-banner" role="note">
      <p>{messages.banner.notice}</p>
    </div>
  );
}
