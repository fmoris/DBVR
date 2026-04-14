import { defineConfig } from "vite";
import path from "node:path";
import mkcert from "vite-plugin-mkcert";

export default defineConfig({
  root: path.resolve(import.meta.dirname, "client"),
  publicDir: path.resolve(import.meta.dirname, "client", "public"),
  plugins: [
    // Punto 4: SSL Automático Robusto
    // Genera certificados confiables para localhost y la red local.
    mkcert({
      hosts: ["localhost", "192.168.3.30"],
      savePath: ".certs", // Ubicación para que el servidor Express los encuentre
    }),
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
