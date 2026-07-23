export const appRoles = ["user", "admin"] as const;

export type AppRole = (typeof appRoles)[number];

export function resolveAppRole(role: unknown): AppRole {
  return role === "admin" ? "admin" : "user";
}

export function hasAdminRole(role: unknown): boolean {
  return resolveAppRole(role) === "admin";
}
