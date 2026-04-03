# Gesture Recipes — Full TypeScript Implementations

All functions assume BabylonJS `WebXRHand` object with `trackedMeshes` available.
Import: `import { WebXRHandJoint } from "@babylonjs/core";`

---

## Helper Utilities

```typescript
import { AbstractMesh, Vector3, WebXRHand, WebXRHandJoint } from "@babylonjs/core";

function joint(hand: WebXRHand, name: string): AbstractMesh {
  return hand.trackedMeshes![WebXRHandJoint[name as keyof typeof WebXRHandJoint]];
}

function dist(hand: WebXRHand, a: string, b: string): number {
  return Vector3.Distance(joint(hand, a).position, joint(hand, b).position);
}

function distSq(hand: WebXRHand, a: string, b: string): number {
  return Vector3.DistanceSquared(joint(hand, a).position, joint(hand, b).position);
}

function fingerBend(hand: WebXRHand, prefix: string): number {
  // Returns 0 (straight) to 1 (fully curled)
  const p = joint(hand, `${prefix}-phalanx-proximal`).position;
  const i = joint(hand, `${prefix}-phalanx-intermediate`).position;
  const d = joint(hand, `${prefix}-phalanx-distal`).position;
  const t = joint(hand, `${prefix}-tip`).position;
  const v1 = i.subtract(p).normalize();
  const v2 = t.subtract(d).normalize();
  const dot = Vector3.Dot(v1, v2); // 1.0=straight, -1.0=max curl
  return (1 - dot) / 2; // normalize 0–1
}

function isExtended(hand: WebXRHand, prefix: string, threshold = 0.3): boolean {
  return fingerBend(hand, prefix) < threshold;
}

function isCurled(hand: WebXRHand, prefix: string, threshold = 0.6): boolean {
  return fingerBend(hand, prefix) > threshold;
}
```

---

## Pinch

**Joints:** thumb-tip, index-finger-tip
**Threshold:** ~0.025m (2.5cm)

```typescript
export function detectPinch(hand: WebXRHand, threshold = 0.025): boolean {
  return distSq(hand, "thumb-tip", "index-finger-tip") < threshold * threshold;
}

// Analog pinch strength 0–1
export function pinchStrength(hand: WebXRHand, maxDist = 0.08): number {
  const d = dist(hand, "thumb-tip", "index-finger-tip");
  return Math.max(0, 1 - d / maxDist);
}
```

---

## Fist

**Joints:** index, middle, ring, pinky — all curled
**No thumb check needed** (thumb position varies too much between people)

```typescript
export function detectFist(hand: WebXRHand): boolean {
  return isCurled(hand, "index-finger") &&
         isCurled(hand, "middle-finger") &&
         isCurled(hand, "ring-finger") &&
         isCurled(hand, "pinky-finger");
}
```

---

## Open Palm

**All 4 fingers extended**

```typescript
export function detectOpenPalm(hand: WebXRHand): boolean {
  return isExtended(hand, "index-finger") &&
         isExtended(hand, "middle-finger") &&
         isExtended(hand, "ring-finger") &&
         isExtended(hand, "pinky-finger");
}
```

---

## Point (Index Extended, Others Curled)

```typescript
export function detectPoint(hand: WebXRHand): boolean {
  return isExtended(hand, "index-finger") &&
         isCurled(hand, "middle-finger") &&
         isCurled(hand, "ring-finger") &&
         isCurled(hand, "pinky-finger");
}
```

---

## Peace Sign (V)

```typescript
export function detectPeace(hand: WebXRHand): boolean {
  return isExtended(hand, "index-finger") &&
         isExtended(hand, "middle-finger") &&
         isCurled(hand, "ring-finger") &&
         isCurled(hand, "pinky-finger");
}
```

---

## Thumbs Up

```typescript
export function detectThumbsUp(hand: WebXRHand): boolean {
  const thumbTip = joint(hand, "thumb-tip").position;
  const wrist    = joint(hand, "wrist").position;
  const thumbAboveWrist = thumbTip.y > wrist.y + 0.05; // thumb is high
  return thumbAboveWrist &&
         isCurled(hand, "index-finger") &&
         isCurled(hand, "middle-finger") &&
         isCurled(hand, "ring-finger") &&
         isCurled(hand, "pinky-finger");
}
```

---

## Gun Shape (Index + Thumb Extended Perpendicular)

```typescript
export function detectGun(hand: WebXRHand): boolean {
  const thumbExtended = dist(hand, "thumb-tip", "thumb-metacarpal") > 0.06;
  return isExtended(hand, "index-finger") &&
         thumbExtended &&
         isCurled(hand, "middle-finger") &&
         isCurled(hand, "ring-finger") &&
         isCurled(hand, "pinky-finger");
}
```

---

## Spread / Star (All Extended + Spread)

```typescript
export function detectSpread(hand: WebXRHand): boolean {
  // All fingers extended
  const allExtended = isExtended(hand, "index-finger") &&
                      isExtended(hand, "middle-finger") &&
                      isExtended(hand, "ring-finger") &&
                      isExtended(hand, "pinky-finger");
  // Check spread: index and pinky tips far apart
  const span = dist(hand, "index-finger-tip", "pinky-finger-tip");
  return allExtended && span > 0.09;
}
```

---

## OK Sign

```typescript
export function detectOK(hand: WebXRHand): boolean {
  const pinchClose = distSq(hand, "thumb-tip", "index-finger-tip") < 0.02 * 0.02;
  return pinchClose &&
         isExtended(hand, "middle-finger") &&
         isExtended(hand, "ring-finger") &&
         isExtended(hand, "pinky-finger");
}
```

---

## Wave (Oscillating Open Palm)

Wave requires motion over time. Track wrist x-position history.

```typescript
export class WaveDetector {
  private _history: number[] = [];
  private _maxHistory = 20; // ~0.66s at 30Hz
  private _dirChanges = 0;
  private _lastDir = 0;

  update(hand: WebXRHand): boolean {
    if (!detectOpenPalm(hand)) {
      this._history = [];
      return false;
    }
    const x = joint(hand, "wrist").position.x;
    this._history.push(x);
    if (this._history.length > this._maxHistory) this._history.shift();

    // Count direction changes
    let changes = 0;
    for (let i = 1; i < this._history.length; i++) {
      const dir = Math.sign(this._history[i] - this._history[i - 1]);
      if (dir !== 0 && dir !== this._lastDir) { changes++; this._lastDir = dir; }
    }
    return changes >= 3; // at least 3 direction reversals = wave
  }
}
```

---

## Two-Hand Gestures

### Clap

```typescript
export function detectClap(leftHand: WebXRHand, rightHand: WebXRHand): boolean {
  const leftPalm  = joint(leftHand,  "wrist").position;
  const rightPalm = joint(rightHand, "wrist").position;
  return Vector3.Distance(leftPalm, rightPalm) < 0.08 &&
         detectOpenPalm(leftHand) &&
         detectOpenPalm(rightHand);
}
```

### Two-Hand Pinch Scale

```typescript
export class TwoHandScaleDetector {
  private _initialDist: number | null = null;

  update(leftHand: WebXRHand, rightHand: WebXRHand): number | null {
    const lPinch = detectPinch(leftHand);
    const rPinch = detectPinch(rightHand);
    if (!lPinch || !rPinch) { this._initialDist = null; return null; }

    const leftPos  = joint(leftHand,  "index-finger-tip").position;
    const rightPos = joint(rightHand, "index-finger-tip").position;
    const currentDist = Vector3.Distance(leftPos, rightPos);

    if (this._initialDist === null) { this._initialDist = currentDist; return 1; }
    return currentDist / this._initialDist; // scale factor
  }
}
```

---

## Wrist Orientation Helpers

```typescript
export function getPalmNormal(hand: WebXRHand): Vector3 {
  const w = joint(hand, "wrist");
  if (!w.rotationQuaternion) return Vector3.Up();
  const m = new Matrix();
  w.rotationQuaternion.toRotationMatrix(m);
  return Vector3.TransformNormal(Vector3.Up(), m).normalize();
}

export function isPalmFacingUp(hand: WebXRHand,    threshold = 0.5): boolean { return getPalmNormal(hand).y >  threshold; }
export function isPalmFacingDown(hand: WebXRHand,  threshold = 0.5): boolean { return getPalmNormal(hand).y < -threshold; }
export function isPalmFacingCamera(hand: WebXRHand, camForward: Vector3): boolean {
  return Vector3.Dot(getPalmNormal(hand), camForward.negate()) > 0.5;
}
```

---

## Debounce Wrapper (prevents flicker)

```typescript
export class DebouncedGesture {
  private _count = 0;
  private _required: number;

  constructor(requiredFrames = 3) { this._required = requiredFrames; }

  check(detected: boolean): boolean {
    this._count = detected ? this._count + 1 : 0;
    return this._count >= this._required;
  }
}

// Usage:
const fistDebounce = new DebouncedGesture(4);
scene.registerBeforeRender(() => {
  if (fistDebounce.check(detectFist(hand))) {
    // stable fist — fire game event
  }
});
```