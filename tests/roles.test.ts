import assert from "node:assert/strict";
import test from "node:test";
import { hasAdminRole, resolveAppRole } from "../convex/roles.ts";

test("existing users without a role remain ordinary users", () => {
  assert.equal(resolveAppRole(undefined), "user");
  assert.equal(resolveAppRole(null), "user");
  assert.equal(hasAdminRole(undefined), false);
});

test("only the exact admin role grants admin authority", () => {
  assert.equal(hasAdminRole("admin"), true);
  assert.equal(hasAdminRole("user"), false);
  assert.equal(hasAdminRole("ADMIN"), false);
  assert.equal(hasAdminRole(true), false);
});
