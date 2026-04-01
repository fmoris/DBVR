---
name: metaquest-webxr
description: >
  Expert guidance for building WebXR games and experiences for Meta Quest headsets using
  Babylon.js, Vite, and TypeScript. Use this skill whenever the user wants to:
  - Build a VR game or 3D experience for Meta Quest (Quest 2, Quest 3, etc.)
  - Set up a Babylon.js + Vite + TypeScript project for WebXR
  - Implement hand tracking, controller input, or XR interactions (grabbing, teleportation, pointers)
  - Optimize a WebXR experience for performance on mobile GPU hardware
  - Deploy or test a WebXR app on a physical Quest device
  - Debug HTTPS/WebXR issues during development
  - Structure a game loop, ECS architecture, or scene management for a Babylon.js game
  Trigger this skill even if the user says "VR web game", "Babylon VR", "Quest browser game",
  "hand tracking web", or any variation of those concepts.
metadata: {
  "openclaw": {
    "emoji": "🥽",
    "requires": {
      "bins": ["node", "npm"]
    },
    "install": [
      {
        "id": "node",
        "kind": "node",
        "label": "Install Node.js (required for Vite + Babylon.js)"
      }
    ]
  }
}
---

# MetaQuest WebXR Game Development with Babylon.js

This skill covers the full stack: **Vite + TypeScript + Babylon.js + WebXR**, optimized for
Meta Quest (Quest 2/3/Pro) running in the built-in Quest browser (Chromium-based).

Read the relevant reference file from `references/` when you need deeper detail:
- `references/project-setup.md` — Scaffolding, Vite config, tsconfig, package.json
- `references/scene-architecture.md` — Engine, Scene, ECS pattern, game loop
- `references/webxr-features.md` — XR session, features list, teleportation, controllers
- `references/hand-tracking.md` — HAND_TRACKING feature, grabbing, near interactions
- `references/performance.md` — Quest GPU limits, draw calls, texture compression, profiling
- `references/deployment.md` — HTTPS dev server, Quest browser, tunneling, deployment

---

## Quick-start Checklist

When the user wants to start a new project from scratch:

1. Scaffold with Vite TypeScript template
2. Install Babylon.js ES6 packages (tree-shaking)
3. Configure `vite.config.ts` with HTTPS for WebXR
4. Create a `BabylonScene` class that owns Engine + Scene
5. Add `WebXRDefaultExperience` with floor meshes
6. Enable desired features (`HAND_TRACKING`, `TELEPORTATION`, etc.)
7. Run dev server accessible over LAN (`--host`) for Quest testing

---

## Core Stack

| Layer | Choice | Notes |
|---|---|---|
| Bundler | Vite 5+ | HMR, fast builds, native ESM |
| Language | TypeScript | Strict mode recommended |
| 3D engine | @babylonjs/core (ES6) | Tree-shakeable; use per-module imports |
| Loaders | @babylonjs/loaders | Required for GLB/GLTF controller models |
| XR types | @types/webxr | Type definitions for WebXR API |

---

## Essential Install

```bash
npm create vite@latest my-xr-game -- --template vanilla-ts
cd my-xr-game
npm install @babylonjs/core @babylonjs/loaders
npm install -D @types/webxr
```

> **Do NOT use `import * from '@babylonjs/core'`** — it blows up bundle size (~4MB).
> Always import from sub-paths for tree-shaking (e.g., `@babylonjs/core/scene.js`).

---

## Minimal Working WebXR Scene

This is the canonical starting point — adapt for any new project:

```typescript
// src/XRScene.ts
import { Engine } from '@babylonjs/core/Engines/engine.js'
import { Scene } from '@babylonjs/core/scene.js'
import { Vector3 } from '@babylonjs/core/Maths/math.vector.js'
import { Color3 } from '@babylonjs/core/Maths/math.color.js'
import { HemisphericLight } from '@babylonjs/core/Lights/hemisphericLight.js'
import { MeshBuilder } from '@babylonjs/core/Meshes/meshBuilder.js'
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial.js'
import { EnvironmentHelper } from '@babylonjs/core/Helpers/environmentHelper'
import { WebXRDefaultExperience } from '@babylonjs/core/XR/webXRDefaultExperience.js'
import { Mesh } from '@babylonjs/core/Meshes/mesh'

// REQUIRED side-effect imports — these register loaders/materials globally
import '@babylonjs/core/Materials/Textures/Loaders'
import '@babylonjs/loaders/glTF'
import '@babylonjs/core/Materials/Node/Blocks'
import '@babylonjs/core/Animations/animatable'

export class XRScene {
  private engine: Engine
  private scene: Scene

  constructor(private canvas: HTMLCanvasElement) {}

  async init(): Promise<void> {
    this.engine = new Engine(this.canvas, true, {
      deterministicLockstep: true,
      lockstepMaxSteps: 4,
    })
    this.scene = new Scene(this.engine)

    // Environment: skybox + ground (ground needed for teleportation)
    const env = new EnvironmentHelper(
      { skyboxSize: 30, groundColor: new Color3(0.5, 0.5, 0.5) },
      this.scene,
    )

    new HemisphericLight('light', new Vector3(0, 1, 0), this.scene).intensity = 0.8

    // Add a simple test object
    const box = MeshBuilder.CreateBox('box', { size: 0.3 }, this.scene)
    box.position.set(0, 1, -1.5)
    const mat = new StandardMaterial('boxMat', this.scene)
    mat.diffuseColor = new Color3(0.2, 0.6, 1.0)
    box.material = mat

    // WebXR — optionalFeatures: true auto-enables teleportation + controllers
    await WebXRDefaultExperience.CreateAsync(this.scene, {
      floorMeshes: [env?.ground as Mesh],
      optionalFeatures: true,
    })

    this.engine.runRenderLoop(() => this.scene.render())
    window.addEventListener('resize', () => this.engine.resize())
  }
}
```

```typescript
// src/main.ts
import { XRScene } from './XRScene'

window.addEventListener('DOMContentLoaded', async () => {
  const canvas = document.getElementById('canvas') as HTMLCanvasElement
  const app = new XRScene(canvas)
  await app.init()
})
```

```html
<!-- index.html -->
<canvas id="canvas" style="width:100%;height:100vh;display:block;touch-action:none;"></canvas>
<script type="module" src="/src/main.ts"></script>
```

---

## Vite Config (with HTTPS for Quest)

WebXR requires HTTPS even on local dev. The Quest browser will refuse to enter an immersive
session over plain HTTP.

```typescript
// vite.config.ts
import { defineConfig } from 'vite'
import basicSsl from '@vitejs/plugin-basic-ssl'

export default defineConfig({
  plugins: [basicSsl()],
  server: {
    host: true,       // expose on LAN so Quest can reach it
    port: 3443,
    https: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
})
```

```bash
npm install -D @vitejs/plugin-basic-ssl
npm run dev -- --host
# Then on Quest browser: https://<your-LAN-IP>:3443
# Accept the self-signed cert warning — Quest allows it
```

---

## Key WebXR Features Available in Babylon.js

Access all features via `xrHelper.featuresManager`:

| Feature name constant | What it does |
|---|---|
| `TELEPORTATION` | Thumbstick teleport + blink transition |
| `POINTER_SELECTION` | Laser pointer ray + trigger select |
| `HAND_TRACKING` | Full 26-joint hand skeleton |
| `BACKGROUND_REMOVER` | AR passthrough (Quest 3) |
| `NEAR_INTERACTION` | Touch-based near-field interaction |
| `WALKING_LOCOMOTION` | Head-bob walking locomotion |
| `HIT_TEST` | AR surface hit testing |

Enable a feature:
```typescript
import { WebXRFeatureName } from '@babylonjs/core/XR/webXRFeaturesManager.js'

const featuresManager = xrHelper.featuresManager
featuresManager.enableFeature(WebXRFeatureName.HAND_TRACKING, 'stable', {
  xrInput: xrHelper.input,
})
```

---

## Hand Tracking + Grabbing Pattern

See `references/hand-tracking.md` for full detail. Quick pattern:

```typescript
import { WebXRHandTracking } from '@babylonjs/core/XR/features/WebXRHandTracking.js'
import { WebXRHandJoint } from '@babylonjs/core/XR/features/WebXRHandTracking.js'
import { WebXRFeatureName } from '@babylonjs/core/XR/webXRFeaturesManager.js'
import { Vector3 } from '@babylonjs/core/Maths/math.vector.js'

const handFeature = xrHelper.featuresManager.enableFeature(
  WebXRFeatureName.HAND_TRACKING, 'stable',
  { xrInput: xrHelper.input }
) as WebXRHandTracking

handFeature.onHandAddedObservable.add((hand) => {
  const indexTip = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)
  const thumbTip = hand.getJointMesh(WebXRHandJoint.THUMB_TIP)
  let grabbed = false

  scene.onBeforeRenderObservable.add(() => {
    const dist = Vector3.Distance(indexTip.position, thumbTip.position)
    if (!grabbed && dist < 0.03 && indexTip.intersectsMesh(targetMesh)) {
      grabbed = true
      targetMesh.setParent(indexTip)  // object follows the finger
    }
    if (grabbed && dist > 0.05) {
      grabbed = false
      targetMesh.setParent(null)
    }
  })
})
```

**Alternative**: Use `SixDofDragBehavior` for built-in smooth grabbing:
```typescript
import { SixDofDragBehavior } from '@babylonjs/core/Behaviors/Meshes/sixDofDragBehavior.js'
mesh.addBehavior(new SixDofDragBehavior())
```

---

## Performance Rules for Quest

Quest 2/3 use mobile Adreno GPUs. Budget carefully:

- **Draw calls**: Stay under ~100/frame. Use `scene.getActiveMeshes().length` to check.
- **Polygons**: Under 300k triangles/frame total.
- **Textures**: Use KTX2/Basis compressed textures. Max 2K for environment, 512px for UI.
- **Materials**: Use `PBRMaterial` only when needed; prefer `StandardMaterial` for simple surfaces.
- **Instancing**: Use `Mesh.createInstance()` for repeated objects (trees, enemies, etc.).
- **Freeze**: Call `scene.freezeActiveMeshes()` for static geometry.
- **Skip debug layer** in production builds — the inspector adds overhead.

---

## Testing Workflow

1. `npm run dev -- --host` → Vite serves at `https://0.0.0.0:3443`
2. Find your LAN IP: `ipconfig` (Windows) / `ifconfig` (Mac/Linux)
3. On Quest browser: `https://<LAN-IP>:3443`
4. Accept the self-signed certificate warning
5. Tap "Enter VR" button that Babylon.js renders automatically
6. Use [WebXR Emulator Chrome Extension](https://github.com/MozillaReality/WebXR-emulator-extension) for desktop testing

---

## Common Gotchas

| Problem | Fix |
|---|---|
| "Enter VR" button missing | Page must be served over HTTPS |
| Controller models don't load | Must import `@babylonjs/loaders/glTF` and `@babylonjs/core/Materials/Node/Blocks` |
| `beginAnimation is not a function` | Import `@babylonjs/core/Animations/animatable` |
| Hand tracking not working | Must be enabled in Quest Settings → Hand & Controllers |
| Scene flickers on Quest | Avoid `engine.clear()` in render loop; let `scene.render()` handle it |
| Teleportation doesn't work | Pass `floorMeshes` to `WebXRDefaultExperience.CreateAsync` |
| Bundle too large | Use per-module imports, not `import * from '@babylonjs/core'` |
