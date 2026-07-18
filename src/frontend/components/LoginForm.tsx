"use client";

import type { FormEvent } from "react";
import { useState } from "react";
import { useLocale } from "@/components/LocaleContext";
import { syncLocalePreference } from "@/lib/locale-api";

type LoginState = {
  kind: "idle" | "success" | "error";
  message: string;
};

export function LoginForm() {
  const { getLocale, messages } = useLocale();
  const [idToken, setIdToken] = useState("");
  const [state, setState] = useState<LoginState>({ kind: "idle", message: "" });
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
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
        return;
      }

      // ログイン成功時点で最新のlocaleをUser#localeへ同期する（Issue #65）。
      // フォーム送信開始時にクロージャで捕捉した値ではなくgetLocale()で読み直すことで、
      // ログイン処理中に言語が切り替わった場合でも古い値で上書きしない
      void syncLocalePreference(getLocale());

      setState({ kind: "success", message: messages.login.success });
      setIdToken("");
    } catch {
      setState({ kind: "error", message: messages.login.error });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form className="login-form" onSubmit={handleSubmit}>
      <label className="field">
        <span className="field__label">{messages.login.idTokenLabel}</span>
        <input
          className="field__input"
          value={idToken}
          onChange={(event) => setIdToken(event.target.value)}
          placeholder={messages.login.idTokenPlaceholder}
          autoComplete="off"
          spellCheck={false}
        />
      </label>

      <div className="login-form__actions">
        <button className="primary-button" type="submit" disabled={submitting || idToken.trim().length === 0}>
          {submitting ? messages.login.submitting : messages.login.submit}
        </button>
        <p className="login-form__hint">{messages.login.hint}</p>
      </div>

      {state.message ? (
        <p className={`status-message status-message--${state.kind}`}>{state.message}</p>
      ) : null}
    </form>
  );
}
