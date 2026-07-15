import { internalMutation } from "./_generated/server";
import { inactiveSessionMs, totalSessionMs } from "./sessionPolicy";

export const applyCurrentSessionPolicy = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const sessions = await ctx.db.query("authSessions").collect();
    let updatedSessions = 0;
    let updatedRefreshTokens = 0;

    for (const session of sessions) {
      // Do not revive sessions or refresh tokens that have already expired.
      if (session.expirationTime < now) continue;

      const sessionExpirationTime = session._creationTime + totalSessionMs;
      if (session.expirationTime !== sessionExpirationTime) {
        await ctx.db.patch(session._id, {
          expirationTime: sessionExpirationTime,
        });
        updatedSessions += 1;
      }

      const refreshTokens = await ctx.db
        .query("authRefreshTokens")
        .withIndex("sessionId", (q) => q.eq("sessionId", session._id))
        .collect();

      for (const refreshToken of refreshTokens) {
        if (
          refreshToken.firstUsedTime !== undefined ||
          refreshToken.expirationTime < now
        ) {
          continue;
        }

        const refreshExpirationTime =
          refreshToken._creationTime + inactiveSessionMs;
        if (refreshToken.expirationTime !== refreshExpirationTime) {
          await ctx.db.patch(refreshToken._id, {
            expirationTime: refreshExpirationTime,
          });
          updatedRefreshTokens += 1;
        }
      }
    }

    return { updatedSessions, updatedRefreshTokens };
  },
});
