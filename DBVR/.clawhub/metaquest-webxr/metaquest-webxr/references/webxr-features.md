# WebXR Features Deep Dive

## WebXRDefaultExperience vs Manual Setup

**DefaultExperience** (recommended for most games):
```typescript
const xrHelper = await WebXRDefaultExperience.CreateAsync(scene, {
  floorMeshes: [groundMesh],
  optionalFeatures: true,        // auto-enables teleportation + pointer selection
  disableTeleportation: false,   // set true to disable default teleportation
  uiOptions: {
    sessionMode: 'immersive-vr', // 'immersive-vr' | 'immersive-ar'
  },
})

// Access sub-components
const camera = xrHelper.baseExperience.camera
const featuresManager = xrHelper.featuresManager
const input = xrHelper.input
```

**Manual setup** (for fine-grained control):
```typescript
import { WebXRExperienceHelper } from '@babylonjs/core/XR/webXRExperienceHelper.js'
import { WebXRSessionManager } from '@babylonjs/core/XR/webXRSessionManager.js'

const xrHelper = await WebXRExperienceHelper.CreateAsync(scene)
await xrHelper.enterXRAsync('immersive-vr', 'local-floor')
```

## All Available Features (WebXRFeatureName)

```typescript
import { WebXRFeatureName } from '@babylonjs/core/XR/webXRFeaturesManager.js'

// Key features:
WebXRFeatureName.TELEPORTATION         // 'xr-controller-teleportation'
WebXRFeatureName.POINTER_SELECTION     // 'xr-controller-pointer-selection'
WebXRFeatureName.HAND_TRACKING         // 'xr-hand-tracking'
WebXRFeatureName.BACKGROUND_REMOVER    // 'xr-background-remover' (AR)
WebXRFeatureName.HIT_TEST              // 'xr-hit-test' (AR)
WebXRFeatureName.NEAR_INTERACTION      // 'xr-near-interaction'
WebXRFeatureName.WALKING_LOCOMOTION    // 'xr-walking-locomotion'
WebXRFeatureName.ANCHOR_SYSTEM        // 'xr-anchor-system'
WebXRFeatureName.PLANE_DETECTION      // 'xr-plane-detection'
```

## Teleportation Configuration

```typescript
import { WebXRMotionControllerTeleportation } from '@babylonjs/core/XR/features/WebXRControllerTeleportation.js'

const teleport = featuresManager.enableFeature(
  WebXRFeatureName.TELEPORTATION,
  'stable',
  {
    xrInput: xrHelper.input,
    floorMeshes: [groundMesh],
    timeToTeleport: 1000,           // ms hold to teleport
    useMainComponentOnly: false,    // if true, only main button
    defaultTargetMeshOptions: {
      torusArrowMaterial: ...,      // customize target ring
    },
  }
) as WebXRMotionControllerTeleportation

// Add/remove floor meshes dynamically
teleport.addFloorMesh(anotherFloor)
teleport.removeFloorMesh(someFloor)

// Snap rotation on thumbstick
teleport.rotationEnabled = true
teleport.rotationAngle = Math.PI / 4  // 45° snap
```

## Pointer Selection (Laser Ray)

```typescript
import { WebXRControllerPointerSelection } from '@babylonjs/core/XR/features/WebXRControllerPointerSelection.js'

const pointerSelection = featuresManager.enableFeature(
  WebXRFeatureName.POINTER_SELECTION,
  'stable',
  {
    xrInput: xrHelper.input,
    enablePointerSelectionOnAllControllers: true,
  }
) as WebXRControllerPointerSelection
```

Make a mesh interactive with pointer:
```typescript
mesh.isPickable = true
mesh.actionManager = new ActionManager(scene)
mesh.actionManager.registerAction(
  new ExecuteCodeAction(ActionManager.OnPickTrigger, () => {
    console.log('Mesh picked in VR!')
  })
)
```

## Controller Input Events

```typescript
xrHelper.input.onControllerAddedObservable.add((controller) => {
  controller.onMotionControllerInitObservable.add((motionController) => {
    // 'trigger', 'squeeze', 'thumbstick', 'a-button', 'b-button', etc.
    const triggerComponent = motionController.getComponentOfType('trigger')
    
    triggerComponent?.onButtonStateChangedObservable.add((component) => {
      if (component.pressed) {
        console.log('Trigger pressed! Value:', component.value)
      }
    })

    const thumbstick = motionController.getComponentOfType('thumbstick')
    thumbstick?.onAxisValueChangedObservable.add((axes) => {
      // axes.x, axes.y — each -1 to 1
    })
  })
})
```

## Entering/Exiting XR Programmatically

```typescript
// Check if WebXR is supported
const supported = await WebXRSessionManager.IsSessionSupportedAsync('immersive-vr')

// Enter XR from code (e.g., custom button)
await xrHelper.baseExperience.enterXRAsync(
  'immersive-vr',
  'local-floor',
  xrHelper.renderTarget
)

// Exit
await xrHelper.baseExperience.exitXRAsync()

// Listen for state changes
xrHelper.baseExperience.onStateChangedObservable.add((state) => {
  // WebXRState: NOT_IN_XR, ENTERING_XR, IN_XR, EXITING_XR
  console.log('XR state:', state)
})
```

## AR Mode (Quest 3 Passthrough)

```typescript
const xrHelper = await WebXRDefaultExperience.CreateAsync(scene, {
  uiOptions: { sessionMode: 'immersive-ar' },
  optionalFeatures: true,
})

// Remove skybox/ground so the real world shows through
featuresManager.enableFeature(WebXRFeatureName.BACKGROUND_REMOVER)
```
