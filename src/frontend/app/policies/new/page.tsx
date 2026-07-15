"use client";

import { PageSection } from "@/components/PageSection";
import { useLocale } from "@/components/LocaleContext";
import { PolicyApplicationWizard } from "@/components/wizard/PolicyApplicationWizard";

export default function NewPolicyPage() {
  const { messages } = useLocale();

  return (
    <PageSection
      title={messages.policies.new.pageTitle}
      description={messages.policies.new.pageDescription}
    >
      <PolicyApplicationWizard />
    </PageSection>
  );
}

