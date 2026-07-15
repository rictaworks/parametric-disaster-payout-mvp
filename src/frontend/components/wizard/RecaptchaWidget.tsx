"use client";

import { useEffect, useRef } from "react";

const SCRIPT_ID = "recaptcha-api-script";

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

    if (window.grecaptcha) {
      renderWidget();
      return;
    }

    const existingScript = document.getElementById(SCRIPT_ID);
    if (existingScript) {
      existingScript.addEventListener("load", renderWidget);
      return () => existingScript.removeEventListener("load", renderWidget);
    }

    const script = document.createElement("script");
    script.id = SCRIPT_ID;
    script.src = "https://www.google.com/recaptcha/api.js";
    script.async = true;
    script.defer = true;
    script.addEventListener("load", renderWidget);
    document.body.appendChild(script);

    return () => script.removeEventListener("load", renderWidget);
  }, [siteKey, onVerify, onExpire]);

  return <div ref={containerRef} className="recaptcha-widget" />;
}
