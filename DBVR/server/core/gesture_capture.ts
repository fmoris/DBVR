import { WebSocketServer } from 'ws';
import { createServer } from 'https';

export interface SSLOptions {
  key: string | Buffer;
  cert: string | Buffer;
}

export function startCaptureServer(port: number = 8080, sslOptions?: SSLOptions) {
  let wss: WebSocketServer;
  
  if (sslOptions) {
    // Create a standalone HTTPS server for WSS
    const httpsServer = createServer(sslOptions);
    wss = new WebSocketServer({ server: httpsServer });
    
    httpsServer.listen(port, () => {
      console.log(`[Capture] 🎙️ Secure Gesture Capture Server (WSS) listening on port ${port}`);
    });
  } else {
    // Fallback to plain WS
    wss = new WebSocketServer({ port });
    console.log(`[Capture] 🎙️ Plain Gesture Capture Server (WS) listening on port ${port}`);
  }

  wss.on('connection', (socket) => {
    console.log('[Capture] 🥽 Quest VR connected for joint streaming');

    socket.on('message', (raw) => {
      try {
        const data = JSON.parse(raw.toString());
        const jointCount = Object.keys(data.joints || {}).length;
        // console.log(`[Capture] Received ${data.hand} hand data (${jointCount} joints) at ${data.timestamp.toFixed(2)}ms`);
      } catch (e) {
        console.error('[Capture] Error parsing joint data:', e);
      }
    });

    socket.on('close', () => {
      console.log('[Capture] 🥽 Quest VR disconnected');
    });
    
    socket.on('error', (err) => {
        console.error('[Capture] WebSocket error:', err);
    });
  });
  
  return wss;
}
