# Scene Architecture & Game Loop

## Engine Initialization Options

```typescript
const engine = new Engine(canvas, true, {
  deterministicLockstep: true,   // Fixed timestep physics
  lockstepMaxSteps: 4,           // Max catch-up steps per frame
  adaptToDeviceRatio: true,      // Pixel ratio scaling (important for Quest)
  powerPreference: 'high-performance',
})
```

## Scene Manager Pattern (Multi-Scene Games)

```typescript
// src/SceneManager.ts
import { Engine } from '@babylonjs/core/Engines/engine.js'
import { Scene } from '@babylonjs/core/scene.js'

export interface IGameScene {
  init(engine: Engine): Promise<Scene>
  update(deltaTime: number): void
  dispose(): void
}

export class SceneManager {
  private engine: Engine
  private activeScene: IGameScene | null = null
  private babylonScene: Scene | null = null

  constructor(engine: Engine) {
    this.engine = engine
    this.engine.runRenderLoop(() => {
      const now = performance.now()
      // delta exposed by Babylon's engine
      const delta = this.engine.getDeltaTime() / 1000
      this.activeScene?.update(delta)
      this.babylonScene?.render()
    })
    window.addEventListener('resize', () => this.engine.resize())
  }

  async loadScene(scene: IGameScene): Promise<void> {
    this.activeScene?.dispose()
    this.babylonScene?.dispose()
    this.babylonScene = await scene.init(this.engine)
    this.activeScene = scene
  }
}
```

## ECS (Entity Component System) Pattern

Recommended for games with many interactive objects:

```typescript
// Component: pure data
interface TransformComponent {
  position: [number, number, number]
  rotation: [number, number, number]
}

interface HealthComponent {
  max: number
  current: number
}

// Entity: just an ID + components map
type ComponentMap = {
  transform?: TransformComponent
  health?: HealthComponent
  // ... add more
}

type EntityId = string
const world = new Map<EntityId, ComponentMap>()

// System: operates on entities with specific components
function healthSystem(world: Map<EntityId, ComponentMap>, dt: number) {
  for (const [id, entity] of world) {
    if (entity.health) {
      // regen example
      entity.health.current = Math.min(
        entity.health.max,
        entity.health.current + dt * 5
      )
    }
  }
}
```

## Game Loop with Fixed Delta

```typescript
let lastTime = performance.now()

engine.runRenderLoop(() => {
  const now = performance.now()
  const deltaTime = Math.min((now - lastTime) / 1000, 0.1) // cap at 100ms
  lastTime = now

  // Run ECS systems
  movementSystem(world, deltaTime)
  physicsSystem(world, deltaTime)
  animationSystem(world, deltaTime)

  scene.render()
})
```

## Debug Layer Toggle (Dev Only)

```typescript
// Toggle inspector with 'I' key during development
window.addEventListener('keydown', (e) => {
  if (e.key === 'i') {
    if (scene.debugLayer.isVisible()) {
      scene.debugLayer.hide()
    } else {
      scene.debugLayer.show({ embedMode: true })
    }
  }
})
```

Import the debug dependencies (dev only — strip in production):
```typescript
import '@babylonjs/core/Debug/debugLayer'
import '@babylonjs/inspector'
```

## Loading GLB/GLTF Assets

```typescript
import { SceneLoader } from '@babylonjs/core/Loading/sceneLoader.js'
import '@babylonjs/loaders/glTF'

// Load into existing scene
const result = await SceneLoader.ImportMeshAsync(
  '',           // meshNames ('' = all)
  '/assets/',   // rootUrl
  'player.glb', // filename
  scene
)
const playerMesh = result.meshes[0]
```

## Babylon.js Observable Pattern

Babylon uses observables instead of EventEmitter:

```typescript
// Subscribe
scene.onBeforeRenderObservable.add(() => {
  // runs every frame before render
})

// One-time subscription
scene.onBeforeRenderObservable.addOnce(() => {
  // runs once
})

// Remove
const observer = scene.onPointerObservable.add((info) => { /* ... */ })
scene.onPointerObservable.remove(observer)
```
