import { useAuthActions } from "@convex-dev/auth/react";
import {
  BadgeCheck,
  KeyRound,
  LockKeyhole,
  MailCheck,
  QrCode,
  ShieldCheck,
} from "lucide-react";
import { FormEvent, useState } from "react";
import {
  authErrorMessage,
  normalizeEmail,
  validateConfirmationCode,
  validatePassword,
} from "./authValidation";

export type AuthMode = "signIn" | "signUp" | "verify";

export function ShellLoading() {
  return (
    <main className="setup-screen">
      <section className="setup-panel compact">
        <p className="setup-mark">TicketLifeline</p>
        <h1>Opening your vault...</h1>
      </section>
    </main>
  );
}

export function AuthScreen({
  initialMode = "signIn",
  initialEmail = "",
}: {
  initialMode?: AuthMode;
  initialEmail?: string;
} = {}) {
  const { signIn } = useAuthActions();
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [email, setEmail] = useState(initialEmail);
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [confirmationCode, setConfirmationCode] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setNotice("");
    setIsSubmitting(true);
    try {
      const cleanEmail = normalizeEmail(email);
      setEmail(cleanEmail);
      if (mode === "verify") {
        const code = validateConfirmationCode(confirmationCode);
        const result = await signIn("password", {
          email: cleanEmail,
          code,
          flow: "email-verification",
        });
        if (!result.signingIn) {
          throw new Error("Could not verify code");
        }
        return;
      }

      validatePassword(password);
      if (mode === "signUp" && password !== confirmPassword) {
        throw new Error("Passwords do not match.");
      }
      const result = await signIn("password", {
        email: cleanEmail,
        password,
        flow: mode,
      });
      if (!result.signingIn) {
        setMode("verify");
        setConfirmationCode("");
        setNotice(
          mode === "signUp"
            ? `We sent a 6-digit confirmation code to ${cleanEmail}.`
            : `This account still needs confirmation. We sent a new code to ${cleanEmail}.`,
        );
      }
    } catch (err) {
      if (err instanceof Error && err.message === "Passwords do not match.") {
        setError(err.message);
      } else {
        setError(authErrorMessage(err));
      }
    } finally {
      setIsSubmitting(false);
    }
  }

  async function resendCode() {
    setError("");
    setNotice("");
    setIsSubmitting(true);
    try {
      const cleanEmail = normalizeEmail(email);
      setEmail(cleanEmail);
      validatePassword(password);
      const result = await signIn("password", {
        email: cleanEmail,
        password,
        flow: "signIn",
      });
      if (!result.signingIn) {
        setNotice(`A new confirmation code was sent to ${cleanEmail}.`);
      }
    } catch (err) {
      setError(authErrorMessage(err));
    } finally {
      setIsSubmitting(false);
    }
  }

  function changeMode(nextMode: AuthMode) {
    setMode(nextMode);
    setPassword("");
    setConfirmPassword("");
    setConfirmationCode("");
    setError("");
    setNotice("");
  }

  const isVerification = mode === "verify";
  const title = mode === "signIn" ? "Sign in" : mode === "signUp" ? "Create account" : "Confirm your email";

  return (
    <main className="auth-screen">
      <section className="auth-copy">
        <div className="brand-row">
          <span className="brand-icon">
            <QrCode size={22} />
          </span>
          <span>TicketLifeline</span>
        </div>
        <h1>Your QR and barcode safety net.</h1>
        <p>
          Save the encoded value behind tickets, coupons, passes, and backup
          codes. No full screenshot storage required.
        </p>
        <div className="assurance-row">
          <ShieldCheck size={18} />
          <span>Per-user vault with compact scan-ready QR patterns.</span>
        </div>
      </section>

      <section className="auth-card">
        <div className="auth-card-header">
          {isVerification ? <MailCheck size={20} /> : <LockKeyhole size={20} />}
          <div>
            <h2>{title}</h2>
            <p>
              {isVerification
                ? "Confirm once to activate your account. Future sign-ins only use email and password."
                : mode === "signIn"
                  ? "Open your vault from any browser with your email and password."
                  : "Use an email you can confirm, then your password works everywhere."}
            </p>
          </div>
        </div>
        <form onSubmit={handleSubmit} className="auth-form">
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="email"
              inputMode="email"
              maxLength={254}
              readOnly={isVerification}
              required
            />
          </label>
          {isVerification ? (
            <label>
              6-digit confirmation code
              <input
                type="text"
                value={confirmationCode}
                onChange={(event) => setConfirmationCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                autoComplete="one-time-code"
                inputMode="numeric"
                pattern="[0-9]{6}"
                maxLength={6}
                autoFocus
                required
              />
            </label>
          ) : (
            <>
              <label>
                Password
                <input
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  autoComplete={mode === "signIn" ? "current-password" : "new-password"}
                  minLength={8}
                  maxLength={128}
                  required
                />
                {mode === "signUp" ? <span className="field-hint">8–128 characters.</span> : null}
              </label>
              {mode === "signUp" ? (
                <label>
                  Confirm password
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(event) => setConfirmPassword(event.target.value)}
                    autoComplete="new-password"
                    minLength={8}
                    maxLength={128}
                    required
                  />
                </label>
              ) : null}
            </>
          )}
          {notice ? <p className="form-notice" role="status">{notice}</p> : null}
          {error ? <p className="form-error" role="alert">{error}</p> : null}
          <button type="submit" className="primary-button" disabled={isSubmitting}>
            {isVerification ? <BadgeCheck size={16} /> : <KeyRound size={16} />}
            {isSubmitting
              ? "Working..."
              : isVerification
                ? "Confirm and sign in"
                : mode === "signIn"
                  ? "Sign in"
                  : "Create vault"}
          </button>
        </form>
        {isVerification ? (
          <div className="auth-secondary-actions">
            <button type="button" className="text-button" onClick={() => void resendCode()} disabled={isSubmitting}>
              Send a new code
            </button>
            <button type="button" className="text-button" onClick={() => changeMode("signIn")} disabled={isSubmitting}>
              Back to sign in
            </button>
          </div>
        ) : (
          <button
            type="button"
            className="text-button"
            onClick={() => changeMode(mode === "signIn" ? "signUp" : "signIn")}
          >
            {mode === "signIn" ? "Need an account?" : "Already have an account?"}
          </button>
        )}
        <a
          className="privacy-link"
          href="https://github.com/jeremyjacob101/TicketLifeline/blob/main/PRIVACY.md"
          target="_blank"
          rel="noreferrer"
        >
          Privacy Policy
        </a>
      </section>
    </main>
  );
}
