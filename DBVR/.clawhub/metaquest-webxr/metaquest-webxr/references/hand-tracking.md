# Hand Tracking Deep Dive

## Enabling Hand Tracking

```typescript
import { WebXRHandTracking, WebXRHandJoint } from '@babylonjs/core/XR/features/WebXRHandTracking.js'
import { WebXRFeatureName } from '@babylonjs/core/XR/webXRFeaturesManager.js'

const handFeature = xrHelper.featuresManager.enableFeature(
  WebXRFeatureName.HAND_TRACKING,
  'stable',
  {
    xrInput: xrHelper.input,
    jointMeshes: {
      enablePhysics: false,       // true enables collision on joints
      physicsProps: { impostorType: PhysicsImpostor.SphereImpostor, mass: 0 },
      returnDefaultTargetMeshIfNotFound: true,
      disableDefaultHandMesh: false,
      handMeshes: {               // optional: replace default hand mesh
        right: customRightMesh,
        left: customLeftMesh,
      },
    },
  }
) as WebXRHandTracking
```

> **Quest Prerequisite**: Hand tracking must be enabled in Quest Settings → Movement Tracking → Hand Tracking.

## All 26 Hand Joints (WebXRHandJoint)

```
WRIST
THUMB_METACARPAL, THUMB_PROXIMAL_PHALANX, THUMB_DISTAL_PHALANX, THUMB_TIP
INDEX_FINGER_METACARPAL, INDEX_FINGER_PROXIMAL_PHALANX, INDEX_FINGER_INTERMEDIATE_PHALANX,
  INDEX_FINGER_DISTAL_PHALANX, INDEX_FINGER_TIP
MIDDLE_FINGER_METACARPAL, MIDDLE_FINGER_PROXIMAL_PHALANX, MIDDLE_FINGER_INTERMEDIATE_PHALANX,
  MIDDLE_FINGER_DISTAL_PHALANX, MIDDLE_FINGER_TIP
RING_FINGER_METACARPAL, RING_FINGER_PROXIMAL_PHALANX, RING_FINGER_INTERMEDIATE_PHALANX,
  RING_FINGER_DISTAL_PHALANX, RING_FINGER_TIP
PINKY_FINGER_METACARPAL, PINKY_FINGER_PROXIMAL_PHALANX, PINKY_FINGER_INTERMEDIATE_PHALANX,
  PINKY_FINGER_DISTAL_PHALANX, PINKY_FINGER_TIP
```

## Grab Detection — Two Approaches

### Approach 1: Pinch (Index + Thumb distance)
Best for: picking up small objects, precision interaction

```typescript
handFeature.onHandAddedObservable.add((hand) => {
  const indexTip = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)
  const thumbTip = hand.getJointMesh(WebXRHandJoint.THUMB_TIP)
  let grabbed: AbstractMesh | null = null
  const GRAB_DIST = 0.03   // 3cm — tune to taste
  const RELEASE_DIST = 0.05

  scene.onBeforeRenderObservable.add(() => {
    const dist = Vector3.Distance(indexTip.position, thumbTip.position)

    if (!grabbed && dist < GRAB_DIST) {
      // Check all grabbable meshes
      for (const mesh of grabbableMeshes) {
        if (indexTip.intersectsMesh(mesh) || thumbTip.intersectsMesh(mesh)) {
          grabbed = mesh
          mesh.setParent(indexTip)
          break
        }
      }
    }

    if (grabbed && dist > RELEASE_DIST) {
      grabbed.setParent(null)
      grabbed = null
    }
  })
})
```

### Approach 2: Pointer Events (Higher-Level)
Babylon.js maps hand pinch to pointer down/up events:

```typescript
// Pointer down = pinch start, Pointer up = pinch release
scene.onPointerObservable.add((info) => {
  if (info.type === PointerEventTypes.POINTERDOWN) {
    const pickedMesh = info.pickInfo?.pickedMesh
    if (pickedMesh?.metadata?.isGrabbable) {
      // start drag
    }
  }
})
```

### Approach 3: SixDofDragBehavior (Recommended for Physics-like Feel)
Best for: general grabbable objects, smooth interaction

```typescript
import { SixDofDragBehavior } from '@babylonjs/core/Behaviors/Meshes/sixDofDragBehavior.js'

const dragBehavior = new SixDofDragBehavior()
dragBehavior.onDragStartObservable.add(() => console.log('grabbed'))
dragBehavior.onDragEndObservable.add(() => console.log('released'))
dragBehavior.allowMultiPointer = false   // single-hand grab

mesh.addBehavior(dragBehavior)
```

## Gesture Detection Patterns

### Fist Detection
```typescript
function isFist(hand: WebXRHand): boolean {
  const joints = [
    WebXRHandJoint.INDEX_FINGER_TIP,
    WebXRHandJoint.MIDDLE_FINGER_TIP,
    WebXRHandJoint.RING_FINGER_TIP,
    WebXRHandJoint.PINKY_FINGER_TIP,
  ]
  const palm = hand.getJointMesh(WebXRHandJoint.WRIST)
  return joints.every(j => {
    const tip = hand.getJointMesh(j)
    return Vector3.Distance(tip.position, palm.position) < 0.08
  })
}
```

### Point Gesture (index extended)
```typescript
function isPointing(hand: WebXRHand): boolean {
  const indexTip = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)
  const indexBase = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_PROXIMAL_PHALANX)
  const middleTip = hand.getJointMesh(WebXRHandJoint.MIDDLE_FINGER_TIP)
  const middleBase = hand.getJointMesh(WebXRHandJoint.MIDDLE_FINGER_PROXIMAL_PHALANX)

  const indexExtended = Vector3.Distance(indexTip.position, indexBase.position) > 0.06
  const middleCurled = Vector3.Distance(middleTip.position, middleBase.position) < 0.04
  return indexExtended && middleCurled
}
```

## Near Interaction (UI Touch)

Babylon.js 7+ supports touchable GUI elements via NEAR_INTERACTION:

```typescript
import { WebXRNearInteraction } from '@babylonjs/core/XR/features/WebXRNearInteraction.js'

const nearInteraction = featuresManager.enableFeature(
  WebXRFeatureName.NEAR_INTERACTION,
  'stable',
  {
    xrInput: xrHelper.input,
    farInteractionFeature: pointerSelection,  // fallback for far interaction
  }
) as WebXRNearInteraction
```

GUI buttons then respond to finger touch automatically.

## Hands + Controllers Simultaneously (Babylon.js 7+)

Quest 3 can detect when the user switches between hands and controllers:

```typescript
xrHelper.input.onControllerAddedObservable.add((controller) => {
  // Could be a hand or a controller
  if (controller.inputSource.hand) {
    // It's a hand
  } else {
    // It's a controller
  }
})
```

## Tips & Gotchas

- `setParent(null)` when releasing is critical — forgetting it permanently attaches the object to your hand mesh
- Adjust grab/release thresholds (`0.03`/`0.05`) based on your object scale
- Hand joint positions are in **world space**, not local space
- The hand mesh is generated at runtime — don't try to access it before `onHandAddedObservable` fires
- On Quest 2, hand tracking can stutter if the room lighting is poor
- Use `Vector3.DistanceSquared` instead of `Vector3.Distance` in hot loops (avoids sqrt)
