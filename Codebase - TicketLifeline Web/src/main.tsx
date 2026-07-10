import { ConvexAuthProvider } from "@convex-dev/auth/react";
import { ConvexReactClient } from "convex/react";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";

const root = createRoot(document.getElementById("root")!);
const convexUrl = import.meta.env.VITE_CONVEX_URL as string | undefined;

root.render(
  <StrictMode>
    {convexUrl ? (
      <ConvexAuthProvider client={new ConvexReactClient(convexUrl)}>
        <App />
      </ConvexAuthProvider>
    ) : (
      <MissingConvexUrl />
    )}
  </StrictMode>,
);

function MissingConvexUrl() {
  return (
    <main className="setup-screen">
      <section className="setup-panel">
        <p className="setup-mark">TicketLifeline</p>
        <h1>Convex is ready to be linked.</h1>
        <p>
          Run <code>npm run convex:dev</code> once and let the Convex CLI create
          the project. It will write <code>VITE_CONVEX_URL</code> into{" "}
          <code>.env.local</code>, then this app will boot into the vault.
        </p>
      </section>
    </main>
  );
}
