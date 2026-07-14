import { useAuthActions } from "@convex-dev/auth/react";
import {
  KeyRound,
  LockKeyhole,
  QrCode,
  ShieldCheck,
} from "lucide-react";
import { FormEvent, useState } from "react";

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

export function AuthScreen() {
  const { signIn } = useAuthActions();
  const [mode, setMode] = useState<"signIn" | "signUp">("signIn");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setIsSubmitting(true);
    try {
      await signIn("password", { username, password, flow: mode });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not sign in.");
    } finally {
      setIsSubmitting(false);
    }
  }

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
          <LockKeyhole size={20} />
          <div>
            <h2>{mode === "signIn" ? "Sign in" : "Create account"}</h2>
            <p>Use a username and password for this first version.</p>
          </div>
        </div>
        <form onSubmit={handleSubmit} className="auth-form">
          <label>
            Username
            <input
              type="text"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              autoComplete="username"
              required
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete={mode === "signIn" ? "current-password" : "new-password"}
              required
            />
          </label>
          {error ? <p className="form-error">{error}</p> : null}
          <button type="submit" className="primary-button" disabled={isSubmitting}>
            <KeyRound size={16} />
            {isSubmitting
              ? "Working..."
              : mode === "signIn"
                ? "Sign in"
                : "Create vault"}
          </button>
        </form>
        <button
          type="button"
          className="text-button"
          onClick={() => setMode((value) => (value === "signIn" ? "signUp" : "signIn"))}
        >
          {mode === "signIn" ? "Need an account?" : "Already have an account?"}
        </button>
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
