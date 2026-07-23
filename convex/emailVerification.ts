const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const brevoEndpoint = "https://api.brevo.com/v3/smtp/email";

export const verificationCodeMaxAgeSeconds = 15 * 60;
export const defaultVerificationSender =
  "TicketLifeline <verify@ticketlifeline.link>";

export function normalizeAndValidateEmail(value: unknown) {
  if (typeof value !== "string") {
    throw new Error("Enter a valid email address.");
  }
  const email = value.trim().toLowerCase();
  if (
    email.length < 3 ||
    email.length > 254 ||
    !emailPattern.test(email)
  ) {
    throw new Error("Enter a valid email address.");
  }
  return email;
}

export function validatePasswordRequirements(password: string) {
  if (password.length < 8) {
    throw new Error("Use a password with at least 8 characters.");
  }
  if (password.length > 128) {
    throw new Error("Use a password with no more than 128 characters.");
  }
}

export function requireCodeForVerificationFlow(flow: unknown, code: unknown) {
  if (flow === "email-verification" && code === undefined) {
    throw new Error("A confirmation code is required.");
  }
}

export async function generateVerificationCode() {
  // Rejection sampling avoids modulo bias while keeping the user-facing code
  // short enough for iOS one-time-code autofill.
  const range = 1_000_000;
  const limit = Math.floor(0x1_0000_0000 / range) * range;
  const random = new Uint32Array(1);
  do {
    crypto.getRandomValues(random);
  } while (random[0] >= limit);
  return String(random[0] % range).padStart(6, "0");
}

export function verificationEmailContent(token: string) {
  if (!/^\d{6}$/.test(token)) {
    throw new Error("Verification code format is invalid.");
  }
  const subject = "Confirm your TicketLifeline email";
  const text = [
    "Confirm your TicketLifeline email",
    "",
    `Your verification code is: ${token}`,
    "",
    "This code expires in 15 minutes. If you did not create a TicketLifeline account, you can ignore this email.",
  ].join("\n");
  const html = `<!doctype html>
<html lang="en">
  <body style="margin:0;background:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#18181b">
    <div style="max-width:520px;margin:0 auto;padding:40px 20px">
      <div style="background:#ffffff;border:1px solid #e4e4e7;border-radius:18px;padding:32px">
        <div style="font-size:14px;font-weight:700;color:#4f46e5;margin-bottom:12px">TicketLifeline</div>
        <h1 style="font-size:24px;line-height:1.2;margin:0 0 12px">Confirm your email</h1>
        <p style="font-size:16px;line-height:1.55;color:#52525b;margin:0 0 24px">Enter this one-time code to finish creating your account.</p>
        <div style="font-size:32px;letter-spacing:8px;font-weight:800;text-align:center;background:#f4f4f5;border-radius:12px;padding:18px 12px">${token}</div>
        <p style="font-size:13px;line-height:1.5;color:#71717a;margin:24px 0 0">The code expires in 15 minutes. After confirmation, future sign-ins use only your email and password. If you did not create this account, ignore this email.</p>
      </div>
    </div>
  </body>
</html>`;
  return { subject, text, html };
}

type SendVerificationEmailOptions = {
  to: string;
  token: string;
  apiKey: string;
  from: string;
  fetchImplementation?: typeof fetch;
};

function parseSender(value: string) {
  const sender = value.trim();
  const namedSender = sender.match(/^([^<>]+?)\s*<([^<>]+)>$/);
  const name = namedSender?.[1].trim();
  const email = normalizeAndValidateEmail(namedSender?.[2] ?? sender);
  return name ? { name, email } : { email };
}

export async function sendVerificationEmail({
  to,
  token,
  apiKey,
  from,
  fetchImplementation = fetch,
}: SendVerificationEmailOptions) {
  if (!apiKey.trim() || !from.trim()) {
    throw new Error("Email delivery is not configured.");
  }
  const email = normalizeAndValidateEmail(to);
  const sender = parseSender(from);
  const content = verificationEmailContent(token);
  const response = await fetchImplementation(brevoEndpoint, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "api-key": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      sender,
      to: [{ email }],
      subject: content.subject,
      textContent: content.text,
      htmlContent: content.html,
      tags: ["email_verification"],
    }),
  });
  if (!response.ok) {
    throw new Error("Verification email could not be delivered. Please try again.");
  }
}
