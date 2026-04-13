import "dotenv/config";
import express from "express";
import fs from "fs";
import path from "path";
import { createServer as createHttpServer } from "http";
import { createServer as createHttpsServer } from "https";
import net from "net";
import { createExpressMiddleware } from "@trpc/server/adapters/express";
import { registerOAuthRoutes } from "./oauth";
import { appRouter } from "../routers";
import { createContext } from "./context";
import { serveStatic, setupVite } from "./vite";
import { networkInterfaces } from "os";
import { startCaptureServer } from "./gesture_capture.js";

function getLanIp(): string {
  const nets = networkInterfaces();
  const ips: string[] = [];
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === "IPv4" && !net.internal) {
        ips.push(net.address);
      }
    }
  }
  const lanIp = ips.find(ip => ip.startsWith("192.168.") || ip.startsWith("10.") || ip.startsWith("172."));
  return lanIp || ips[0] || "localhost";
}

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
  let sslOptions: any = undefined;


  if (process.env.NODE_ENV === "development") {
    try {
      const lanIp = getLanIp();

      console.log(`[Server] Generando certificado SSL para: ${lanIp}`);

      // selfsigned v5 es async — devuelve Promise<{private, public, cert, fingerprint}>
      const { generate } = await import("selfsigned");
      const pems = await generate(
        [{ name: "commonName", value: lanIp }],
        {
          keySize: 2048,
          algorithm: "sha256",
          extensions: [
            {
              name: "subjectAltName",
              altNames: [
                { type: 2, value: "localhost" },
                { type: 2, value: lanIp },
                { type: 7, ip: "127.0.0.1" },
                { type: 7, ip: lanIp },
              ],
            },
          ],
        }
      );

      sslOptions = { key: pems.private, cert: pems.cert };
      server = createHttpsServer(sslOptions, app);

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
 
  // --- GESTURE SYNC ENDPOINT ---
  app.post("/api/gestures/sync", async (req, res) => {
    try {
      const { characterId, model } = req.body;
      if (!characterId || !model) {
        return res.status(400).json({ error: "Faltan characterId o model" });
      }
 
      const dataDir = path.join(process.cwd(), "server", "data", "gestures");
      if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
      }
 
      const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
      const filename = `gestures_${characterId}_${timestamp}.json`;
      const filePath = path.join(dataDir, filename);
 
      fs.writeFileSync(filePath, JSON.stringify(model, null, 2));
      console.log(`[Sync] 💾 Modelo guardado para ${characterId}: ${filename}`);
      
      res.json({ success: true, filename });
    } catch (error: any) {
      console.error("[Sync] Error guardando gesto:", error);
      res.status(500).json({ error: error.message });
    }
  // --- GESTURE LATEST ENDPOINT ---
  app.get("/api/gestures/latest/:characterId", async (req, res) => {
    try {
      const { characterId } = req.params;
      const dataDir = path.join(process.cwd(), "server", "data", "gestures");
      
      if (!fs.existsSync(dataDir)) {
        return res.status(404).json({ error: "No hay datos de gestos cargados" });
      }
 
      const files = fs.readdirSync(dataDir)
        .filter(f => f.startsWith(`gestures_${characterId}_`) && f.endsWith(".json"))
        .sort(); // Sorting alphabetically works for ISO timestamps
 
      if (files.length === 0) {
        return res.status(404).json({ error: "No se encontraron modelos para este personaje" });
      }
 
      const latestFile = files[files.length - 1];
      const content = fs.readFileSync(path.join(dataDir, latestFile), "utf-8");
      
      console.log(`[Sync] 📥 Entregando modelo más reciente para ${characterId}: ${latestFile}`);
      res.json({ 
        characterId, 
        filename: latestFile, 
        model: JSON.parse(content) 
      });
    } catch (error: any) {
      console.error("[Sync] Error recuperando modelo:", error);
      res.status(500).json({ error: error.message });
    }
  });

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

  // Start Secure Isolated Gesture Capture Server on Port 8080
  startCaptureServer(8080, sslOptions);

  server.listen(port, () => {

    const protocol = isHttps ? "https" : "http";
    const wsProtocol = isHttps ? "wss" : "ws";
    const lanIp = getLanIp();
    const host = lanIp !== "localhost" ? lanIp : "localhost";

    console.log(`Server running on ${protocol}://${host}:${port}/`);
    if (process.env.NODE_ENV === "development" && isHttps) {
      console.log(`[WebXR] Abre ${protocol}://${host}:${port}/ y acepta el certificado`);
      console.log(`[WebXR] En Meta Quest usa: ${protocol}://${lanIp}:${port}/`);
      console.log(`[Capture] Secure WebSocket ready on ${wsProtocol}://${lanIp}:${port}/ws/gestures`);
    }
  });

}

startServer().catch(console.error);

