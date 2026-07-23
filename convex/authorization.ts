import { getAuthUserId } from "@convex-dev/auth/server";
import type { Doc } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { hasAdminRole, resolveAppRole } from "./roles";

type AuthenticatedCtx = QueryCtx | MutationCtx;

export async function requireCurrentUser(
  ctx: AuthenticatedCtx,
): Promise<Doc<"users">> {
  const userId = await getAuthUserId(ctx);
  if (!userId) {
    throw new Error("Not authenticated");
  }

  const user = await ctx.db.get(userId);
  if (!user) {
    throw new Error("Account no longer exists");
  }
  return user;
}

export async function requireAdmin(
  ctx: AuthenticatedCtx,
): Promise<Doc<"users">> {
  const user = await requireCurrentUser(ctx);
  if (!hasAdminRole(user.role)) {
    throw new Error("Admin access required");
  }
  return user;
}

export function publicAccountProfile(user: Doc<"users">) {
  const role = resolveAppRole(user.role);
  return {
    id: user._id,
    email: user.email,
    name: user.name,
    role,
    isAdmin: role === "admin",
  };
}
