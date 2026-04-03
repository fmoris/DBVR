---
name: webxr-gesture-game
description: >
  Expert skill for hand gesture systems in WebXR video games with BabylonJS. Use IMMEDIATELY when user wants to: detect or respond to hand gestures in VR (fist, pinch, point, wave, thumbs-up, open-palm, custom); build gesture-driven mechanics (spells, throwing, blocking, charging); set up WebXRHandTracking joint-based input; detect gesture combos or sequences; map hand poses to game actions (shoot, grab, jump, dash); calibrate finger joint distances or wrist angles; animate hands in response to gestures; troubleshoot hand tracking bugs. Trigger for: "gesture", "hand tracking", "pinch", "fist", "WebXR hands", "VR input", "hand pose", "finger detection", or any game mechanic triggered by hand movement.
---

# WebXR Gesture Game Skill — BabylonJS

Skill for building robust, game-ready hand gesture systems in WebXR using BabylonJS. Covers the full pipeline: hand tracking setup → joint reading → gesture detection → combo sequences → game action dispatch.

---

## 1. Core Architecture

### Hand Tracking Setup (BabylonJS)

```typescript
import { WebXRHandTracking, WebXRFeatureName } from "@babylonjs/core";

const xr = await scene.createDefaultXRExperienceAsync({
  uiOptions: { sessionMode: "immersive-vr" },
  optionalFeatures: true,
});

const handFeature = xr.baseExperience.featuresManager.enableFeature(
  WebXRFeatureName.HAND_TRACKING,
  "latest",
  {
    xrInput: xr.input,
    jointMeshes: { invisible: true }, // hide default spheres for performance
  }
) as WebXRHandTracking;
```

### Accessing Joint Meshes

BabylonJS exposes **25 joint meshes** per hand via `hand.trackedMeshes` (array indexed by XRHandJoint enum).

```typescript
handFeature.onHandAddedObservable.add((hand) => {
  scene.registerBeforeRender(() => {
    if (!hand.trackedMeshes) return;
    const indexTip = hand.trackedMeshes[WebXRHandJoint["index-finger-tip"]];
    const thumbTip = hand.trackedMeshes[WebXRHandJoint["thumb-tip"]];
    const wrist   = hand.trackedMeshes[WebXRHandJoint["wrist"]];
    // use positions for gesture math
  });
});
```

### Key Joint Indices (WebXR spec, 25 joints per hand)

| Joint Name | Index | Use for |
|---|---|---|
| wrist | 0 | palm orientation, hand position |
| thumb-metacarpal | 1 | thumb base |
| thumb-tip | 4 | pinch detection |
| index-finger-metacarpal | 5 | pointer base |
| index-finger-tip | 9 | pinch, point detection |
| middle-finger-tip | 14 | fist check |
| ring-finger-tip | 19 | fist check |
| pinky-finger-tip | 24 | fist check |
| index-finger-phalanx-proximal | 6 | bend angle calc |
| index-finger-phalanx-intermediate | 7 | bend angle calc |

---

## 2. Gesture Detection Patterns

### Pattern A — Distance-Based (fast, ~150KB, Meta Quest friendly)

Compare distances between key joints. Best for poses (static shapes).

```typescript
function getDistance(a: AbstractMesh, b: AbstractMesh): number {
  return Vector3.Distance(a.position, b.position);
}

function isPinch(hand: WebXRHand, threshold = 0.025): boolean {
  const thumb = hand.trackedMeshes![WebXRHandJoint["thumb-tip"]];
  const index = hand.trackedMeshes![WebXRHandJoint["index-finger-tip"]];
  return getDistance(thumb, index) < threshold;
}
```

### Pattern B — Dot Product / Bend Angle (for fist, point, spread)

Calculate if a finger is curled or extended using direction vectors between joints.

```typescript
function isFingerExtended(hand: WebXRHand, fingerPrefix: string): boolean {
  const proximal     = hand.trackedMeshes![WebXRHandJoint[`${fingerPrefix}-phalanx-proximal`]];
  const intermediate = hand.trackedMeshes![WebXRHandJoint[`${fingerPrefix}-phalanx-intermediate`]];
  const distal       = hand.trackedMeshes![WebXRHandJoint[`${fingerPrefix}-phalanx-distal`]];
  const tip          = hand.trackedMeshes![WebXRHandJoint[`${fingerPrefix}-tip`]];

  const v1 = intermediate.position.subtract(proximal.position).normalize();
  const v2 = tip.position.subtract(distal.position).normalize();
  const dot = Vector3.Dot(v1, v2); // ~1.0 = straight, ~0 or negative = curled
  return dot > 0.7;
}

function isFist(hand: WebXRHand): boolean {
  return ["index-finger", "middle-finger", "ring-finger", "pinky-finger"]
    .every(f => !isFingerExtended(hand, f));
}

function isPointing(hand: WebXRHand): boolean {
  return isFingerExtended(hand, "index-finger") &&
    !isFingerExtended(hand, "middle-finger") &&
    !isFingerExtended(hand, "ring-finger");
}
```

### Pattern C — Wrist Orientation (for "palm up", "palm down", etc.)

```typescript
function getWristNormal(hand: WebXRHand): Vector3 {
  const wrist  = hand.trackedMeshes![WebXRHandJoint["wrist"]];
  // wrist.rotationQuaternion encodes palm orientation
  const palmUp = new Vector3(0, 1, 0);
  return Vector3.TransformNormal(palmUp, Matrix.FromQuaternionToRef(
    wrist.rotationQuaternion!, new Matrix()
  ));
}

function isPalmFacingUp(hand: WebXRHand): boolean {
  return getWristNormal(hand).y > 0.6;
}
```

---

## 3. Gesture Library — Game-Ready Poses

For each gesture, Claude should implement a detector function following Pattern A/B/C above and emit events through a GestureEmitter (see Section 4).

| Gesture | Detection Strategy | Game Use Cases |
|---|---|---|
| **Pinch** | thumb-tip ↔ index-tip distance < 0.025m | select, shoot, grab |
| **Fist** | all 4 fingers curled (dot < 0.5) | charge attack, hold block |
| **Open Palm** | all 4 fingers extended + thumb | stop, push, shield |
| **Point** | index extended, others curled | aim, cursor, cast ray |
| **Peace / V** | index + middle extended, others curled | special ability |
| **Thumbs Up** | thumb extended upward, fist base | confirm, boost |
| **Gun** | index + thumb extended perpendicular | shoot, precision aim |
| **Spread / Star** | all 5 fingers extended + spread | explosion, AoE blast |
| **OK** | thumb + index circle, others extended | lock-on, portal |
| **Wave** | open palm + wrist yaw oscillation over time | greet, activate, hail |

Read `references/gesture-recipes.md` for full implementations of each.

---

## 4. GestureEmitter — Central Event System

Always funnel detection through a central emitter so game systems subscribe cleanly.

```typescript
import { Observable } from "@babylonjs/core";

export type GestureEvent = {
  gesture: string;   // "pinch" | "fist" | "wave" | custom
  hand: "left" | "right" | "both";
  position: Vector3; // wrist world position
  intensity?: number; // 0–1 for analog gestures (squeeze pressure)
};

export class GestureEmitter {
  onGestureDetected = new Observable<GestureEvent>();
  onGestureReleased = new Observable<GestureEvent>();

  private _active = new Map<string, boolean>();

  emit(event: GestureEvent) {
    const key = `${event.hand}_${event.gesture}`;
    if (!this._active.get(key)) {
      this._active.set(key, true);
      this.onGestureDetected.notifyObservers(event);
    }
  }

  release(event: GestureEvent) {
    const key = `${event.hand}_${event.gesture}`;
    if (this._active.get(key)) {
      this._active.set(key, false);
      this.onGestureReleased.notifyObservers(event);
    }
  }
}
```

---

## 5. Combo / Sequence System

For gesture combos (charge → release, fist → point → open), use a state machine:

```typescript
type ComboStep = { gesture: string; hand: "left" | "right" | "both"; holdMs?: number };

class GestureCombo {
  private _step = 0;
  private _stepStartTime = 0;

  constructor(
    private steps: ComboStep[],
    private onComplete: () => void,
    private timeoutMs = 2000
  ) {}

  advance(event: GestureEvent, now: number) {
    const current = this.steps[this._step];
    if (now - this._stepStartTime > this.timeoutMs) this._step = 0; // timeout reset

    if (event.gesture === current.gesture && event.hand === current.hand) {
      if (current.holdMs) {
        // needs hold — check duration on release
        this._stepStartTime = now;
      }
      this._step++;
      if (this._step >= this.steps.length) {
        this.onComplete();
        this._step = 0;
      }
    }
  }
}

// Example: Kamehameha — fist (both) → hold 500ms → open palm (both)
const kamehameha = new GestureCombo([
  { gesture: "fist", hand: "both", holdMs: 500 },
  { gesture: "openPalm", hand: "both" },
], () => castBeam());
```

---

## 6. Performance Guidelines for Meta Quest / Low-End VR

- **Only sample 6–8 joints** per gesture (not all 25). Read `references/joint-selection.md` for per-gesture maps.
- Run gesture checks at **max 30Hz** (not every frame). Use a timer accumulator:
  ```typescript
  let _elapsed = 0;
  scene.registerBeforeRender(() => {
    _elapsed += scene.deltaTime;
    if (_elapsed < 33) return; // ~30Hz
    _elapsed = 0;
    checkAllGestures();
  });
  ```
- **Debounce** gesture detection: require N consecutive frames before emitting. Prevents flicker.
- Use **WebWorker** for heavy gesture math if > 8 gestures active simultaneously.
- Processing 5–6 gestures has zero measurable FPS impact on Quest hardware.
- Avoid distance checks using `Vector3.Distance` in hot paths — prefer `distanceSquared` and compare to `threshold²`.

---

## 7. Gesture Calibration Workflow

When fine-tuning thresholds:
1. Add a **debug overlay** that logs joint distances live in the headset.
2. Capture raw values for each intended gesture via a calibration mode.
3. Set threshold = `(min_detected + max_not_detected) / 2` with 10–15% margin.
4. Export thresholds as JSON (transferable between games).

Read `references/calibration-guide.md` for the full BabylonJS debug overlay code.

---

## 8. Hand Animation Playback (Tutorial Hints)

Show pre-recorded gesture animations so users learn poses:

```typescript
import { AnimatedHand } from "@clickon/webxr-extension"; // community extension

const hint = new AnimatedHand(scene);
await hint.loadModel("generic-hand", "left");
hint.playAnimation(capturedGestureData); // show user the correct pose
```

- Record gesture animations via `IHandTrackingXRFeatEnv` capture methods.
- Keep recordings < 300 KB (use binary packaging).
- Play in a floating UI panel before gameplay begins.

---

## 9. Common Game Mechanic Patterns

### Spell Casting (charge + release)
```
Both fists held > 1s → energy particle effect builds up
Both palms open → projectile fires in look direction
```

### Object Grab & Throw
```
Fist while hand mesh intersects object → parent object to wrist joint
Open palm → release, apply velocity = wrist velocity at release frame
```

### Shield Block
```
Open palm facing camera → spawn shield mesh at palm position
Palm normal = shield facing direction (update every frame)
```

### Locomotion (point & teleport)
```
Point gesture → raycast from index-tip in finger direction
Pinch to confirm → teleport player to hit point
```

### Two-Hand Scaling
```
Pinch both hands simultaneously → measure distance between pinch points
Scale target object by (current_dist / initial_dist)
```

---

## 10. Reference Files

Read these when you need deeper implementation details:

- `references/gesture-recipes.md` — Complete TypeScript implementations for every gesture in the library (Section 3)
- `references/joint-selection.md` — Which joints to sample for each gesture (performance optimization)
- `references/calibration-guide.md` — Debug overlay + threshold calibration workflow
- `references/combo-examples.md` — Full combo system examples: Kamehameha, combo chains, hold-and-release patterns

---

## Quick Reference: BabylonJS API Cheatsheet

```typescript
// Enable hand tracking
featuresManager.enableFeature(WebXRFeatureName.HAND_TRACKING, "latest", { xrInput });

// Access hands
handFeature.onHandAddedObservable.add((hand: WebXRHand) => { ... });
handFeature.onHandRemovedObservable.add((hand: WebXRHand) => { ... });

// Joint mesh access
hand.trackedMeshes![jointIndex].position  // world position
hand.trackedMeshes![jointIndex].rotationQuaternion  // world rotation

// Handedness
hand.xrController.inputSource.handedness // "left" | "right"

// Pinch detection (built-in)
hand.getJointMesh("index-finger-tip")  // alternative access by name
```