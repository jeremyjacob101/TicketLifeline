import { useSyncExternalStore } from "react";

const mobileMediaQuery = "(max-width: 820px)";

function subscribe(onChange: () => void) {
  if (typeof window === "undefined") return () => undefined;

  const mediaQuery = window.matchMedia(mobileMediaQuery);
  mediaQuery.addEventListener("change", onChange);
  return () => mediaQuery.removeEventListener("change", onChange);
}

function getSnapshot() {
  return typeof window !== "undefined" && window.matchMedia(mobileMediaQuery).matches
    ? "mobile"
    : "desktop";
}

function getServerSnapshot() {
  return "desktop";
}

export function useDeviceType() {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
