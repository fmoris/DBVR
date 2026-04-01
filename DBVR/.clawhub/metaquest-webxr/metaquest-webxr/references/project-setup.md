# Project Setup Reference

## Full package.json

```json
{
  "name": "my-xr-game",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@babylonjs/core": "^7.0.0",
    "@babylonjs/loaders": "^7.0.0"
  },
  "devDependencies": {
    "@types/webxr": "^0.5.0",
    "@vitejs/plugin-basic-ssl": "^1.0.0",
    "typescript": "^5.0.0",
    "vite": "^5.0.0"
  }
}
```

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "strict": true
  },
  "include": ["src"]
}
```

## Recommended Directory Structure

```
my-xr-game/
├── index.html
├── vite.config.ts
├── tsconfig.json
├── package.json
├── public/
│   └── assets/           ← static GLBs, audio, images
└── src/
    ├── main.ts            ← entry point
    ├── XRScene.ts         ← engine + scene init
    ├── scenes/            ← multiple scene classes
    │   ├── GameScene.ts
    │   └── MenuScene.ts
    ├── entities/          ← game objects (ECS)
    ├── systems/           ← update systems
    ├── components/        ← data components
    └── xr/
        ├── HandTracker.ts
        └── XRInput.ts
```

## Vite Config — Full Options

```typescript
import { defineConfig } from 'vite'
import basicSsl from '@vitejs/plugin-basic-ssl'

export default defineConfig({
  plugins: [basicSsl()],
  root: './',
  publicDir: 'public',
  server: {
    host: true,
    port: 3443,
    https: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        // Split Babylon.js into its own chunk for better caching
        manualChunks: {
          babylon: ['@babylonjs/core', '@babylonjs/loaders'],
        },
      },
    },
  },
  optimizeDeps: {
    // Ensure Babylon's side-effect imports are pre-bundled correctly
    include: ['@babylonjs/core', '@babylonjs/loaders'],
  },
})
```

## Adding Vue or React (Optional)

For apps that need a 2D HUD/menu layer:

```bash
# Vue
npm install vue
npm install -D @vitejs/plugin-vue

# React
npm install react react-dom
npm install -D @vitejs/plugin-react
```

Mount the 3D canvas separately from the UI layer — never let the framework control the canvas element directly.

## Scene Data with JSON (ECS Data-Driven Approach)

```json
// data/scene.json
{
  "entities": {
    "Player": {
      "components": {
        "Movement": {
          "position": [0, 0, 0],
          "walkingSpeed": 1.0
        },
        "Health": { "max": 100, "current": 100 }
      }
    }
  }
}
```

Load at runtime:
```typescript
const sceneData = await fetch('/data/scene.json').then(r => r.json())
```
