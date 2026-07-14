import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const webRoot = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  root: webRoot,
  envDir: repoRoot,
  plugins: [react()],
  resolve: {
    alias: {
      "@ticketlifeline/convex-api": fileURLToPath(
        new URL("../convex/_generated/api.js", import.meta.url),
      ),
      "@ticketlifeline/convex-data-model": fileURLToPath(
        new URL("../convex/_generated/dataModel.d.ts", import.meta.url),
      ),
    },
  },
});
