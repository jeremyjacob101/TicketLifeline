import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  // The shared Convex connection settings live at the repository root.
  envDir: "..",
  plugins: [react()],
});
