import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { normalizeAndValidateEmail } from "./emailVerification";

// Intentionally internal: clients can never promote themselves or another user.
// Run this from the trusted Convex dashboard or CLI when an account role changes.
export const setRoleByEmail = internalMutation({
  args: {
    email: v.string(),
    role: v.union(v.literal("user"), v.literal("admin")),
  },
  handler: async (ctx, args) => {
    const email = normalizeAndValidateEmail(args.email);
    const user = await ctx.db
      .query("users")
      .withIndex("email", (q) => q.eq("email", email))
      .unique();

    if (!user) {
      throw new Error("No account exists for that email address.");
    }

    await ctx.db.patch(user._id, { role: args.role });
    return {
      userId: user._id,
      email,
      role: args.role,
    };
  },
});
