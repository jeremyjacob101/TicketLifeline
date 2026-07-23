import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultVerificationSender,
  generateVerificationCode,
  normalizeAndValidateEmail,
  requireCodeForVerificationFlow,
  sendVerificationEmail,
  validatePasswordRequirements,
  verificationEmailContent,
} from "../convex/emailVerification.ts";

test("server auth validation accepts only normalized emails and valid passwords", () => {
  assert.equal(
    normalizeAndValidateEmail(" JeremyJacob101@Gmail.com "),
    "jeremyjacob101@gmail.com",
  );
  assert.doesNotThrow(() => validatePasswordRequirements("12345678"));
  assert.throws(() => normalizeAndValidateEmail("invalid"), /valid email/);
  assert.throws(() => validatePasswordRequirements("short"), /at least 8/);
  assert.throws(
    () => requireCodeForVerificationFlow("email-verification", undefined),
    /confirmation code/,
  );
});

test("verification codes and email content use the six-digit contract", async () => {
  const code = await generateVerificationCode();
  assert.match(code, /^\d{6}$/);
  const content = verificationEmailContent("012345");
  assert.match(content.subject, /Confirm/);
  assert.match(content.text, /012345/);
  assert.match(content.html, /012345/);
  assert.throws(() => verificationEmailContent("12345"), /format/);
});

test("Brevo delivery uses the authenticated sender without leaking the key", async () => {
  let request: { url?: string; init?: RequestInit } = {};
  const fetchImplementation: typeof fetch = async (input, init) => {
    request = { url: String(input), init };
    return new Response(null, { status: 201 });
  };

  await sendVerificationEmail({
    to: " Person@Example.com ",
    token: "123456",
    apiKey: "test-secret",
    from: defaultVerificationSender,
    fetchImplementation,
  });

  assert.equal(request.url, "https://api.brevo.com/v3/smtp/email");
  assert.equal(request.init?.method, "POST");
  assert.equal(
    new Headers(request.init?.headers).get("api-key"),
    "test-secret",
  );
  const body = JSON.parse(String(request.init?.body));
  assert.deepEqual(body.sender, {
    name: "TicketLifeline",
    email: "verify@ticketlifeline.link",
  });
  assert.deepEqual(body.to, [{ email: "person@example.com" }]);
  assert.equal(JSON.stringify(body).includes("test-secret"), false);
});

test("Brevo delivery fails safely when configuration or delivery fails", async () => {
  await assert.rejects(
    sendVerificationEmail({
      to: "person@example.com",
      token: "123456",
      apiKey: "",
      from: defaultVerificationSender,
    }),
    /not configured/,
  );
  await assert.rejects(
    sendVerificationEmail({
      to: "person@example.com",
      token: "123456",
      apiKey: "test-secret",
      from: defaultVerificationSender,
      fetchImplementation: async () => new Response(null, { status: 400 }),
    }),
    /could not be delivered/,
  );
});
