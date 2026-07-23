import assert from "node:assert/strict";
import test from "node:test";
import {
  authErrorMessage,
  normalizeEmail,
  validateConfirmationCode,
  validatePassword,
} from "../Codebase - TicketLifeline Web/src/authValidation.ts";

test("web auth validation normalizes email and validates credentials", () => {
  assert.equal(normalizeEmail("  Person@Example.COM "), "person@example.com");
  assert.equal(validateConfirmationCode(" 123456 "), "123456");
  assert.doesNotThrow(() => validatePassword("12345678"));
  assert.throws(() => normalizeEmail("not-an-email"), /valid email/);
  assert.throws(() => validatePassword("short"), /at least 8/);
  assert.throws(() => validateConfirmationCode("12345"), /6-digit/);
});

test("web auth errors never expose unexpected backend details", () => {
  assert.equal(
    authErrorMessage(new Error("Invalid credentials")),
    "Email or password is incorrect.",
  );
  assert.equal(
    authErrorMessage(new Error("[Request ID: secret] Uncaught server stack")),
    "We could not complete that request. Please try again.",
  );
});
