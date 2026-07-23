export function normalizeEmail(value: string) {
  const email = value.trim().toLowerCase();
  if (
    email.length < 3 ||
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error("Enter a valid email address.");
  }
  return email;
}

export function validatePassword(password: string) {
  if (password.length < 8) {
    throw new Error("Use a password with at least 8 characters.");
  }
  if (password.length > 128) {
    throw new Error("Use a password with no more than 128 characters.");
  }
}

export function validateConfirmationCode(value: string) {
  const code = value.trim();
  if (!/^\d{6}$/.test(code)) {
    throw new Error("Enter the 6-digit confirmation code.");
  }
  return code;
}

export function authErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const normalized = message.toLowerCase();
  if (normalized.includes("invalid credentials")) {
    return "Email or password is incorrect.";
  }
  if (normalized.includes("could not verify code") || normalized.includes("invalid code")) {
    return "That confirmation code is incorrect or expired. Request a new code and try again.";
  }
  if (normalized.includes("already exists")) {
    return "An account already exists for this email. Sign in instead.";
  }
  if (normalized.includes("too many") || normalized.includes("rate limit")) {
    return "Too many attempts. Wait a few minutes and try again.";
  }
  if (
    normalized.includes("email delivery is not configured") ||
    normalized.includes("verification email could not be delivered")
  ) {
    return "We could not send the confirmation email. Please try again shortly.";
  }
  if (
    normalized.includes("network") ||
    normalized.includes("failed to fetch") ||
    normalized.includes("load failed")
  ) {
    return "Could not connect to TicketLifeline. Check your connection and try again.";
  }
  if (
    normalized.includes("valid email") ||
    normalized.includes("at least 8") ||
    normalized.includes("no more than 128") ||
    normalized.includes("6-digit")
  ) {
    return message;
  }
  return "We could not complete that request. Please try again.";
}
