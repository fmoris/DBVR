# Deployment & Testing Workflow

## Development → Quest Testing

### Step 1: Run local HTTPS dev server

```bash
npm run dev -- --host
# Output: https://192.168.x.x:3443
```

### Step 2: Quest browser access

1. Open the Quest browser (Meta Quest Browser)
2. Navigate to `https://<your-LAN-IP>:3443`
3. Tap **"Advanced"** → **"Proceed to site"** to bypass self-signed cert warning
4. Scene loads in 2D mode; tap **"Enter VR"** to go immersive

> The cert warning is expected with `@vitejs/plugin-basic-ssl`. Self-signed certs work fine for Quest development.

### Step 3: Iterating

Vite's HMR (Hot Module Replacement) reloads automatically when you save — no need to refresh the Quest browser manually (for non-XR changes). For XR feature changes, you'll need to exit and re-enter VR.

## Desktop Testing with WebXR Emulator

For fast iteration without wearing the headset:

1. Install [WebXR API Emulator](https://github.com/MozillaReality/WebXR-emulator-extension) for Chrome/Firefox
2. Open DevTools → **WebXR** tab
3. Choose device (Meta Quest 2/3 profile available)
4. The "Enter VR" button becomes active in the browser

Limitation: the emulator is cumbersome for hand tracking tests — do those on the device.

## Tunneling (for sharing with others)

If you need to share a dev build externally (e.g., testing with a team):

```bash
# Option 1: ngrok
ngrok http https://localhost:3443

# Option 2: cloudflared
cloudflared tunnel --url https://localhost:3443
```

Both provide an HTTPS tunnel URL. Quest can access it from anywhere.

## Production Build

```bash
npm run build
# Outputs to dist/
```

Check bundle size:
```bash
npx vite-bundle-visualizer
# or
ls -lh dist/assets/*.js
```

Target: `< 1MB` for the main app chunk; Babylon.js vendor chunk can be 500–600KB gzipped.

## Hosting Options

| Option | Notes |
|--------|-------|
| **GitHub Pages** | Free, HTTPS auto, good for demos |
| **Netlify** | Drop `dist/` folder, instant HTTPS |
| **Vercel** | Auto-deploy from Git, free tier |
| **Cloudflare Pages** | Fast CDN, free tier |
| **itch.io** | Game-focused, supports WebGL/WebXR |

All require HTTPS — all listed options provide it automatically.

### GitHub Pages Example

```yaml
# .github/workflows/deploy.yml
name: Deploy to GitHub Pages
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run build
      - uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./dist
```

## Quest Developer Mode (for sideloading)

Not required for WebXR (browser-based). WebXR apps run in the Quest browser without developer mode. Only needed if building native APKs.

## Debugging on Device

### Enable Quest remote debugging

1. Connect Quest to PC via USB
2. In Quest: **Settings → System → Developer → USB Connection Dialog → Enable**
3. In Chrome desktop: `chrome://inspect/#devices`
4. Find the Quest browser tab and click **Inspect**

This gives you full Chrome DevTools (console, profiler, network) for the running WebXR session.

### Common Console Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `WebXR requires HTTPS` | HTTP on localhost | Use HTTPS dev server |
| `Build of NodeMaterial failed` | Missing import | Add `@babylonjs/core/Materials/Node/Blocks` |
| `beginAnimation is not a function` | Missing import | Add `@babylonjs/core/Animations/animatable` |
| `Cannot read properties of undefined (reading 'ground')` | EnvironmentHelper not awaited | Await `EnvironmentHelper` setup |
| `XRSession already exists` | Double init | Guard with `if (!xrHelper)` check |
| Controller model 404 | Missing GLTF loader | Add `@babylonjs/loaders/glTF` |

## Cross-Platform Checklist

Before shipping, verify on:
- [ ] Meta Quest 2 browser (Chrome 72fps target)
- [ ] Meta Quest 3 browser (Chrome 90fps target)
- [ ] Desktop Chrome + WebXR emulator
- [ ] Desktop Firefox + WebXR emulator (optional)
- [ ] iOS Safari (WebXR limited — immersive-vr may not work, only `inline`)
