"use client";

import { useEffect, useRef } from "react";

const SCRIPT_ID = "recaptcha-api-script";
const ONLOAD_CALLBACK_NAME = "__pdpRecaptchaOnLoad";

type RecaptchaRenderParams = {
  sitekey: string;
  callback: (token: string) => void;
  "expired-callback": () => void;
};

declare global {
  interface Window {
    grecaptcha?: {
      render: (container: HTMLElement, params: RecaptchaRenderParams) => number;
      reset: (widgetId?: number) => void;
    };
    __pdpRecaptchaOnLoad?: () => void;
  }
}

type RecaptchaWidgetProps = {
  siteKey: string;
  onVerify: (token: string) => void;
  onExpire: () => void;
};

export function RecaptchaWidget({ siteKey, onVerify, onExpire }: RecaptchaWidgetProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const widgetIdRef = useRef<number | null>(null);

  useEffect(() => {
    function renderWidget() {
      if (!containerRef.current || !window.grecaptcha || widgetIdRef.current !== null) {
        return;
      }

      widgetIdRef.current = window.grecaptcha.render(containerRef.current, {
        sitekey: siteKey,
        callback: onVerify,
        "expired-callback": onExpire,
      });
    }

    if (window.grecaptcha && typeof window.grecaptcha.render === "function") {
      renderWidget();
      return;
    }

    window.__pdpRecaptchaOnLoad = renderWidget;

    if (document.getElementById(SCRIPT_ID)) {
      return;
    }

    const script = document.createElement("script");
    script.id = SCRIPT_ID;
    script.src = `https://www.google.com/recaptcha/api.js?onload=${ONLOAD_CALLBACK_NAME}&render=explicit`;
    script.async = true;
    script.defer = true;
    document.body.appendChild(script);
  }, [siteKey, onVerify, onExpire]);

  return <div ref={containerRef} className="recaptcha-widget" />;
}
