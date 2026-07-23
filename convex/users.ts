import { getAuthUserId } from "@convex-dev/auth/server";
import { mutation, query } from "./_generated/server";
import { publicAccountProfile, requireCurrentUser } from "./authorization";

export const me = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireCurrentUser(ctx);
    return publicAccountProfile(user);
  },
});

export const deleteAccount = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (!userId) {
      throw new Error("Not authenticated");
    }

    const [passes, accounts, sessions] = await Promise.all([
      ctx.db
        .query("passes")
        .withIndex("by_owner_updated", (q) => q.eq("ownerId", userId))
        .collect(),
      ctx.db
        .query("authAccounts")
        .withIndex("userIdAndProvider", (q) => q.eq("userId", userId))
        .collect(),
      ctx.db
        .query("authSessions")
        .withIndex("userId", (q) => q.eq("userId", userId))
        .collect(),
    ]);

    const verificationCodeGroups = await Promise.all(
      accounts.map((account) =>
        ctx.db
          .query("authVerificationCodes")
          .withIndex("accountId", (q) => q.eq("accountId", account._id))
          .collect(),
      ),
    );
    const rateLimitRecords = await Promise.all(
      accounts.map((account) =>
        ctx.db
          .query("authRateLimits")
          .withIndex("identifier", (q) => q.eq("identifier", account._id))
          .unique(),
      ),
    );
    const refreshTokenGroups = await Promise.all(
      sessions.map((session) =>
        ctx.db
          .query("authRefreshTokens")
          .withIndex("sessionId", (q) => q.eq("sessionId", session._id))
          .collect(),
      ),
    );
    const verifierGroups = await Promise.all(
      sessions.map((session) =>
        ctx.db
          .query("authVerifiers")
          .withIndex("sessionId", (q) => q.eq("sessionId", session._id))
          .collect(),
      ),
    );

    for (const pass of passes) await ctx.db.delete(pass._id);
    for (const codes of verificationCodeGroups) {
      for (const code of codes) await ctx.db.delete(code._id);
    }
    for (const rateLimit of rateLimitRecords) {
      if (rateLimit) await ctx.db.delete(rateLimit._id);
    }
    for (const tokens of refreshTokenGroups) {
      for (const token of tokens) await ctx.db.delete(token._id);
    }
    for (const verifiers of verifierGroups) {
      for (const verifier of verifiers) await ctx.db.delete(verifier._id);
    }
    for (const session of sessions) await ctx.db.delete(session._id);
    for (const account of accounts) await ctx.db.delete(account._id);
    await ctx.db.delete(userId);

    return { deletedPasses: passes.length };
  },
});
