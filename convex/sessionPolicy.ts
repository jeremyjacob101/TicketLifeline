export const dayMs = 1000 * 60 * 60 * 24;
export const inactiveSessionMs = dayMs * 30 * 6;
// Convex Auth requires a finite total duration. One hundred years makes the
// six-month rolling inactivity window the practical session limit.
export const totalSessionMs = dayMs * 365 * 100;
