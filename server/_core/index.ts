import "dotenv/config";
import express from "express";
import { createServer as createHttpServer } from "http";
import { createServer as createHttpsServer } from "https";
import net from "net";
import { createExpressMiddleware } from "@trpc/server/adapters/express";
import { registerOAuthRoutes } from "./oauth";
import { appRouter } from "../routers";
import { createContext } from "./context";
import { serveStatic, setupVite } from "./vite";

function isPortAvailable(port: number): Promise<boolean> {
  return new Promise(resolve => {
    const server = net.createServer();
    server.listen(port, () => {
      server.close(() => resolve(true));
    });
    server.on("error", () => resolve(false));
  });
}

async function findAvailablePort(startPort: number = 3000): Promise<number> {
  for (let port = startPort; port < startPort + 20; port++) {
    if (await isPortAvailable(port)) {
      return port;
    }
  }
  throw new Error(`No available port found starting from ${startPort}`);
}

async function startServer() {
  const app = express();

  // En desarrollo: HTTPS con certificado autofirmado (requerido por WebXR immersive-vr).
  // En producción: HTTP simple (el proxy/CDN provee TLS).
  let server: ReturnType<typeof createHttpServer> | ReturnType<typeof createHttpsServer>;
  let isHttps = false;

  if (process.env.NODE_ENV === "development") {
    try {
      // selfsigned v5 es async — devuelve Promise<{private, public, cert, fingerprint}>
      const { generate } = await import("selfsigned");
      const pems = await generate(
        [{ name: "commonName", value: "localhost" }],
        {
          keySize: 2048,
          algorithm: "sha256",
          extensions: [
            {
              name: "subjectAltName",
              altNames: [
                { type: 2, value: "localhost" },
                { type: 7, ip: "127.0.0.1" },
              ],
            },
          ],
        }
      );
      server = createHttpsServer({ key: pems.private, cert: pems.cert }, app);
      isHttps = true;
      console.log("[Server] HTTPS habilitado — WebXR disponible");
    } catch (e) {
      console.warn("[Server] No se pudo crear HTTPS, usando HTTP:", e);
      server = createHttpServer(app);
    }
  } else {
    server = createHttpServer(app);
  }

  // Configure body parser with larger size limit for file uploads
  app.use(express.json({ limit: "50mb" }));
  app.use(express.urlencoded({ limit: "50mb", extended: true }));

  // OAuth callback under /api/oauth/callback
  registerOAuthRoutes(app);

  // tRPC API
  app.use(
    "/api/trpc",
    createExpressMiddleware({
      router: appRouter,
      createContext,
    })
  );

  // development mode uses Vite, production mode uses static files
  if (process.env.NODE_ENV === "development") {
    await setupVite(app, server as any);
  } else {
    serveStatic(app);
  }

  const preferredPort = parseInt(process.env.PORT || "3000");
  const port = await findAvailablePort(preferredPort);

  if (port !== preferredPort) {
    console.log(`Port ${preferredPort} is busy, using port ${port} instead`);
  }

  server.listen(port, () => {
    const protocol = isHttps ? "https" : "http";
    console.log(`Server running on ${protocol}://localhost:${port}/`);
    if (process.env.NODE_ENV === "development" && isHttps) {
      console.log(`[WebXR] Abre ${protocol}://localhost:${port}/ y acepta el certificado`);
      console.log(`[WebXR] En Meta Quest usa: ${protocol}://<IP-de-tu-PC>:${port}/`);
    }
  });
}

startServer().catch(console.error);
