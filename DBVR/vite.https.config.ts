import { defineConfig } from "vite";
import path from "node:path";

export default defineConfig({
  root: path.resolve(import.meta.dirname, "client"),
  publicDir: path.resolve(import.meta.dirname, "client", "public"),
  resolve: {
    alias: {
      "@shared": path.resolve(import.meta.dirname, "shared"),
    },
  },
  build: {
    outDir: path.resolve(import.meta.dirname, "dist/public"),
    emptyOutDir: true,
    target: "ES2020",
  },
  server: {
    host: true,
    https: true,
    allowedHosts: true,
    port: 3000,
  },
});