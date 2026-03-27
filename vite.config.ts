import { defineConfig } from "vite";
import path from "node:path";
import basicSsl from "@vitejs/plugin-basic-ssl";

export default defineConfig({
  root: path.resolve(import.meta.dirname, "client"),
  publicDir: path.resolve(import.meta.dirname, "client", "public"),
  plugins: [
    // Genera certificado TLS compatible con Chrome/Edge para desarrollo local.
    // Requerido por WebXR (immersive-vr solo funciona en HTTPS o localhost seguro).
    basicSsl(),
  ],
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
    allowedHosts: [
      ".manuspre.computer",
      ".manus.computer",
      ".manus-asia.computer",
      ".manuscomputer.ai",
      ".manusvm.computer",
      "localhost",
      "127.0.0.1",
    ],
  },
});
