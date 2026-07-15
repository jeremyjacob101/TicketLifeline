import { Password } from "@convex-dev/auth/providers/Password";
import { convexAuth } from "@convex-dev/auth/server";
import { inactiveSessionMs, totalSessionMs } from "./sessionPolicy";

function normalizeUsername(value: string) {
  return value.trim().toLowerCase();
}

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  session: {
    totalDurationMs: totalSessionMs,
    inactiveDurationMs: inactiveSessionMs,
  },
  providers: [
    Password({
      profile(params) {
        const username =
          typeof params.username === "string"
            ? normalizeUsername(params.username)
            : typeof params.email === "string"
              ? normalizeUsername(params.email)
              : "";

        if (!username) {
          throw new Error("Missing username");
        }

        return { email: username, username, name: username };
      },
    }),
  ],
});
