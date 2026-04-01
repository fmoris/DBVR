# Performance Optimization for Meta Quest

## Quest GPU Budget (Rule of Thumb)

| Budget | Quest 2 | Quest 3 |
|--------|---------|---------|
| Target FPS | 72 fps | 90 fps (120 capable) |
| Draw calls | ≤ 100 | ≤ 150 |
| Triangles | ≤ 300k | ≤ 500k |
| Texture memory | ≤ 512MB | ≤ 1GB |
| Max texture size | 2048×2048 | 4096×4096 |

Quest is a **mobile Adreno GPU** — it cannot match PC VR. Be aggressive with optimization.

## Profiling in Babylon.js

```typescript
// Enable performance counter
scene.enableScenePerformancePriority = true  // auto-applies optimizations

// Check active mesh count
console.log('Active meshes:', scene.getActiveMeshes().length)

// Babylon's built-in performance monitor
const perf = new PerformanceMonitor()
engine.runRenderLoop(() => {
  perf.enable()
  console.log('FPS:', engine.getFps().toFixed())
  scene.render()
})
```

## Reduce Draw Calls

### Instancing (same mesh, many positions)
```typescript
const base = MeshBuilder.CreateBox('base', { size: 0.2 }, scene)
base.isVisible = false  // hide source mesh

for (let i = 0; i < 100; i++) {
  const instance = base.createInstance(`box_${i}`)
  instance.position.set(Math.random() * 10 - 5, 0.1, Math.random() * 10 - 5)
}
// All 100 instances = 1 draw call
```

### Merging Static Meshes
```typescript
import { Mesh } from '@babylonjs/core/Meshes/mesh.js'

const merged = Mesh.MergeMeshes(
  [mesh1, mesh2, mesh3],
  true,  // disposeSource
  true,  // allow32BitsIndices
  undefined,
  false, // subdivideWithSubMeshes
  true,  // multiMultiMaterials
)
```

### Freeze Active Meshes (Static Scenes)
```typescript
scene.freezeActiveMeshes()
// Call scene.unfreezeActiveMeshes() if scene changes
```

## Texture Optimization

### KTX2 / Basis Compressed Textures
```bash
# Install basisu CLI tool
npm install -g basisu

# Compress a PNG
basisu texture.png -ktx2 -mipmap -quality_level 200
```

Load in Babylon.js (auto-detected by extension):
```typescript
const mat = new PBRMaterial('mat', scene)
mat.albedoTexture = new Texture('/textures/floor.ktx2', scene)
```

### Texture Size Guidelines
- Environment/skybox: 2048×2048 max
- Character textures: 512×512 or 1024×1024
- UI panels: 256×256 when possible
- Lightmaps: 512×512, baked offline

## LOD (Level of Detail)

```typescript
import { Mesh } from '@babylonjs/core/Meshes/mesh.js'

const highDetail = /* load or build high-poly mesh */
const lowDetail = /* build low-poly version */

highDetail.addLODLevel(5, lowDetail)   // use lowDetail beyond 5 units
highDetail.addLODLevel(15, null)       // invisible beyond 15 units
```

## Material Optimization

- Use **StandardMaterial** instead of PBRMaterial when PBR features are not needed (no reflections/metallic)
- Bake **ambient occlusion** and **shadows** into lightmap textures — no real-time shadows on Quest
- Disable `scene.shadowsEnabled` — shadows are expensive
- Reuse material instances across meshes

```typescript
// BAD: one material per mesh
meshes.forEach(m => { m.material = new StandardMaterial(...) })

// GOOD: one material shared
const sharedMat = new StandardMaterial('shared', scene)
meshes.forEach(m => { m.material = sharedMat })
```

## Render Pipeline Optimization

```typescript
// Disable post-processing if not needed
scene.postProcessesEnabled = false

// Disable fog on Quest
scene.fogEnabled = false

// Reduce shadow quality / disable
scene.shadowsEnabled = false

// Only render what's in view
scene.skipFrustumClipping = false  // keep frustum culling ON

// Reduce particles
particleSystem.maxActiveParticleCount = 500  // keep low
```

## Audio Optimization

```typescript
import { Sound } from '@babylonjs/core/Audio/sound.js'
import '@babylonjs/core/Audio/audioEngine'  // required side-effect

const sound = new Sound('jump', '/assets/jump.ogg', scene, null, {
  autoplay: false,
  loop: false,
  spatialSound: true,  // 3D positional audio in VR
})
```

Use `.ogg` format — Quest browser supports it with smaller file sizes than MP3.

## Network / Asset Loading

- Pre-load all GLB assets before entering XR (`SceneLoader.ImportMeshAsync` before `enterXRAsync`)
- Use Babylon's `AssetsManager` for batched loading with progress
- Avoid loading assets after XR starts — it causes frame drops

```typescript
import { AssetsManager } from '@babylonjs/core/Misc/assetsManager.js'

const manager = new AssetsManager(scene)

const task = manager.addMeshTask('player', '', '/assets/', 'player.glb')
task.onSuccess = (t) => { /* use t.loadedMeshes */ }

manager.onFinish = (tasks) => { /* all done — safe to enter XR */ }
await manager.loadAsync()
```

## Scene Optimizer

Babylon includes a built-in optimizer that degrades quality to maintain FPS:

```typescript
import { SceneOptimizer, SceneOptimizerOptions } from '@babylonjs/core/Misc/sceneOptimizer.js'

const options = SceneOptimizerOptions.ModerateDegradationAllowed(60)  // target 60fps
SceneOptimizer.OptimizeAsync(scene, options, () => {
  console.log('Optimization succeeded')
}, () => {
  console.log('Could not reach target FPS')
})
```
