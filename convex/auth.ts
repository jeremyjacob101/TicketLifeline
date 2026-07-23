import { Email } from "@convex-dev/auth/providers/Email";
import { Password } from "@convex-dev/auth/providers/Password";
import { convexAuth } from "@convex-dev/auth/server";
import {
  defaultVerificationSender,
  generateVerificationCode,
  normalizeAndValidateEmail,
  requireCodeForVerificationFlow,
  sendVerificationEmail,
  validatePasswordRequirements,
  verificationCodeMaxAgeSeconds,
} from "./emailVerification";
import { inactiveSessionMs, totalSessionMs } from "./sessionPolicy";

const verificationSender =
  process.env.AUTH_EMAIL_FROM ?? defaultVerificationSender;
const brevoApiKey =
  process.env.BREVO_API_KEY ??
  process.env.TICKETLIFELINE_CONVEX_BREVO_API_KEY ??
  process.env.TICKETLIFELINE_BREVO_API_KEY ??
  "";

const emailVerification = Email({
  id: "email-verification",
  from: verificationSender,
  maxAge: verificationCodeMaxAgeSeconds,
  generateVerificationToken: generateVerificationCode,
  async sendVerificationRequest({ identifier, token }) {
    await sendVerificationEmail({
      to: identifier,
      token,
      apiKey: brevoApiKey,
      from: verificationSender,
    });
  },
});

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  session: {
    totalDurationMs: totalSessionMs,
    inactiveDurationMs: inactiveSessionMs,
  },
  providers: [
    Password({
      profile(params) {
        requireCodeForVerificationFlow(params.flow, params.code);
        const email = normalizeAndValidateEmail(params.email);
        return { email, role: "user" as const };
      },
      validatePasswordRequirements,
      verify: emailVerification,
    }),
  ],
});
