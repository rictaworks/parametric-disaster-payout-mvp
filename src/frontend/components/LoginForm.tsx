"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { useLocale } from "@/components/LocaleContext";
import { syncLocalePreference } from "@/lib/locale-api";

const GOOGLE_GSI_SCRIPT_ID = "google-identity-services-script";
const GOOGLE_GSI_SCRIPT_SRC = "https://accounts.google.com/gsi/client";
const GOOGLE_BUTTON_OPTIONS = {
  theme: "outline",
  size: "large",
  text: "signin_with",
  shape: "rectangular",
  logo_alignment: "left",
  width: "100%",
} as const;

type LoginState = {
  kind: "idle" | "success" | "error";
  message: string;
};

type SessionState = "checking" | "unauthenticated" | "authenticated";

type GoogleCredentialResponse = {
  credential?: string;
};

type GoogleIdentityButton = {
  initialize: (options: {
    client_id: string;
    callback: (response: GoogleCredentialResponse) => void;
  }) => void;
  renderButton: (container: HTMLElement, options: typeof GOOGLE_BUTTON_OPTIONS) => void;
};

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: GoogleIdentityButton;
      };
    };
  }
}

export function LoginForm() {
  const { getLocale, messages } = useLocale();
  const [state, setState] = useState<LoginState>({ kind: "idle", message: "" });
  const [sessionState, setSessionState] = useState<SessionState>("checking");
  const [submitting, setSubmitting] = useState(false);
  const [loggingOut, setLoggingOut] = useState(false);
  const buttonRef = useRef<HTMLDivElement | null>(null);
  const submittingRef = useRef(false);
  const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;

  useEffect(() => {
    let cancelled = false;

    async function loadSession() {
      try {
        const response = await fetch("/api/v1/session", {
          method: "GET",
        });

        if (cancelled) {
          return;
        }

        if (response.ok) {
          setSessionState("authenticated");
          return;
        }

        setSessionState("unauthenticated");
      } catch {
        if (!cancelled) {
          setSessionState("unauthenticated");
        }
      }
    }

    void loadSession();

    return () => {
      cancelled = true;
    };
  }, []);

  const submitIdToken = useCallback(
    async (idToken: string) => {
      if (submittingRef.current) {
        return false;
      }
      submittingRef.current = true;
      setSubmitting(true);
      setState({ kind: "idle", message: "" });

      try {
        const response = await fetch("/api/v1/session", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ id_token: idToken }),
        });

        if (!response.ok) {
          setState({ kind: "error", message: messages.login.error });
          return false;
        }

        // ログイン成功時点で最新のlocaleをUser#localeへ同期する（Issue #65）。
        // フォーム送信開始時にクロージャで捕捉した値ではなくgetLocale()で読み直すことで、
        // ログイン処理中に言語が切り替わった場合でも古い値で上書きしない
        void syncLocalePreference(getLocale());

        setSessionState("authenticated");
        setState({ kind: "success", message: messages.login.success });
        return true;
      } catch {
        setState({ kind: "error", message: messages.login.error });
        return false;
      } finally {
        setSubmitting(false);
        submittingRef.current = false;
      }
    },
    [getLocale, messages.login.error, messages.login.success]
  );

  const handleLogout = useCallback(async () => {
    if (loggingOut) {
      return;
    }

    setLoggingOut(true);
    setState({ kind: "idle", message: "" });

    try {
      const response = await fetch("/api/v1/session", {
        method: "DELETE",
      });

      if (!response.ok) {
        setState({ kind: "error", message: messages.login.error });
        return;
      }

      setSessionState("unauthenticated");
      setState({ kind: "success", message: messages.login.loggedOut });
    } catch {
      setState({ kind: "error", message: messages.login.error });
    } finally {
      setLoggingOut(false);
    }
  }, [loggingOut, messages.login.error, messages.login.loggedOut]);

  const handleCredentialResponse = useCallback(
    (response: GoogleCredentialResponse) => {
      if (submittingRef.current) {
        return;
      }
      if (!response.credential) {
        setState({ kind: "error", message: messages.login.error });
        return;
      }

      void submitIdToken(response.credential);
    },
    [messages.login.error, submitIdToken]
  );

  useEffect(() => {
    let cancelled = false;

    function renderGoogleButton() {
      if (cancelled || sessionState !== "unauthenticated" || !buttonRef.current || !clientId) {
        return;
      }

      const googleIdentity = window.google?.accounts?.id;
      if (!googleIdentity) {
        return;
      }

      googleIdentity.initialize({
        client_id: clientId,
        callback: handleCredentialResponse,
      });
      googleIdentity.renderButton(buttonRef.current, GOOGLE_BUTTON_OPTIONS);
    }

    function handleScriptError() {
      if (!cancelled) {
        setState({ kind: "error", message: messages.login.error });
      }
    }

    if (sessionState !== "unauthenticated") {
      return () => {
        cancelled = true;
      };
    }

    if (window.google?.accounts?.id) {
      renderGoogleButton();
      return () => {
        cancelled = true;
      };
    }

    const existingScript = document.getElementById(GOOGLE_GSI_SCRIPT_ID);
    if (existingScript) {
      existingScript.addEventListener("load", renderGoogleButton);
      existingScript.addEventListener("error", handleScriptError);

      return () => {
        cancelled = true;
        existingScript.removeEventListener("load", renderGoogleButton);
        existingScript.removeEventListener("error", handleScriptError);
      };
    }

    if (!clientId) {
      return () => {
        cancelled = true;
      };
    }

    const script = document.createElement("script");
    script.id = GOOGLE_GSI_SCRIPT_ID;
    script.src = GOOGLE_GSI_SCRIPT_SRC;
    script.async = true;
    script.defer = true;
    script.addEventListener("load", renderGoogleButton);
    script.addEventListener("error", handleScriptError);
    document.body.appendChild(script);

    return () => {
      cancelled = true;
      script.removeEventListener("load", renderGoogleButton);
      script.removeEventListener("error", handleScriptError);
    };
  }, [clientId, handleCredentialResponse, messages.login.error, sessionState]);

  return (
    <div className="login-form">
      <div className="field">
        <span className="field__label">
          {sessionState === "authenticated" ? messages.login.loggedIn : messages.login.title}
        </span>
        {sessionState === "authenticated" ? (
          <p className="status-message status-message--success">{messages.login.loggedIn}</p>
        ) : clientId ? (
          <div ref={buttonRef} className="google-login-button" aria-label={messages.login.title} />
        ) : (
          <p className="status-message status-message--error">{messages.login.googleUnavailable}</p>
        )}
      </div>

      <div className="login-form__actions">
        {sessionState === "authenticated" ? (
          <>
            <Link href="/mypage" className="secondary-button">
              {messages.navigation.mypage}
            </Link>
            <button className="primary-button" type="button" onClick={() => void handleLogout()} disabled={loggingOut}>
              {messages.login.logout}
            </button>
          </>
        ) : (
          <p className="login-form__hint">{messages.login.hint}</p>
        )}
      </div>

      {submitting ? <p className="status-message">{messages.login.submitting}</p> : null}
      {state.message ? <p className={`status-message status-message--${state.kind}`}>{state.message}</p> : null}
    </div>
  );
}
