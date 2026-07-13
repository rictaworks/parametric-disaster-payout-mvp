'use client';

import { useT } from '@/lib/i18n';
import type { WizardState } from '@/lib/types';

const stepKeys = ['wizard_step1', 'wizard_step2', 'wizard_step3', 'wizard_step4', 'wizard_step5'] as const;

export function StepBar({ currentStep }: { currentStep: WizardState['step'] }) {
  const t = useT();

  return (
    <div className="mb-8 overflow-x-auto">
      <div className="flex min-w-[720px] items-start justify-between gap-3">
        {stepKeys.map((stepKey, index) => {
          const stepNumber = (index + 1) as WizardState['step'];
          const done = currentStep > stepNumber;
          const active = currentStep === stepNumber;

          return (
            <div key={stepKey} className="flex flex-1 items-center gap-3">
              <div className="flex flex-col items-center gap-2 text-center">
                <div
                  className={[
                    'step-circle',
                    done ? 'step-circle-done' : '',
                    active ? 'step-circle-active' : ''
                  ].join(' ')}
                >
                  {done ? <i className="fa-solid fa-check" aria-hidden="true" /> : <span>{stepNumber}</span>}
                </div>
                <div className="text-xs text-muted">{t(stepKey)}</div>
              </div>
              {index < stepKeys.length - 1 ? <div className="h-px flex-1 bg-border" /> : null}
            </div>
          );
        })}
      </div>
    </div>
  );
}
