"use client";

import { useLocale } from "@/components/LocaleContext";
import { LoginForm } from "@/components/LoginForm";
import { PageSection } from "@/components/PageSection";

export default function LoginPage() {
  const { messages } = useLocale();

  return (
    <PageSection title={messages.login.title} description={messages.login.description}>
      <div className="stack">
        <p className="eyebrow">{messages.login.eyebrow}</p>
        <LoginForm />
      </div>
    </PageSection>
  );
}
