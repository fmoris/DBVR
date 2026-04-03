# Combo Examples & Calibration Guide

---

## Combo System — Full Examples

### Kamehameha (Dragon Ball-style beam)

```typescript
// Step 1: both fists held together (wrists close) for 800ms
// Step 2: push both open palms forward

const kamehameha = new GestureCombo(
  [
    { gesture: "fist",     hand: "both", holdMs: 800 },
    { gesture: "openPalm", hand: "both" },
  ],
  () => {
    spawnBeam(scene.activeCamera!.position, scene.activeCamera!.getForwardRay().direction);
  },
  { timeoutMs: 3000 }
);
```

### Combo Chain (Street Fighter-style)

```typescript
// jab → cross → uppercut = special move
const streetCombo = new GestureCombo(
  [
    { gesture: "point", hand: "right" },
    { gesture: "point", hand: "left" },
    { gesture: "thumbsUp", hand: "right" }, // uppercut shape
  ],
  () => specialAttack(),
  { timeoutMs: 1500, strictOrder: true }
);
```

### Hold & Charge

```typescript
export class HoldGesture {
  private _startTime: number | null = null;

  update(detected: boolean, now: number, requiredMs = 1000): number {
    // Returns 0–1 charge level, 1 = fully charged
    if (!detected) { this._startTime = null; return 0; }
    if (this._startTime === null) this._startTime = now;
    return Math.min(1, (now - this._startTime) / requiredMs);
  }
}

// Usage:
const chargeGesture = new HoldGesture();
scene.registerBeforeRender(() => {
  const charge = chargeGesture.update(detectFist(rightHand), performance.now(), 1500);
  updateChargeVFX(charge);
  if (charge >= 1 && detectOpenPalm(rightHand)) fireChargedAttack();
});
```

### Telekinesis (sustained point at object)

```typescript
export class TekinesisDwell {
  private _target: AbstractMesh | null = null;
  private _dwellStart = 0;
  private _requiredMs = 600;

  update(hand: WebXRHand, scene: Scene, now: number): AbstractMesh | null {
    if (!detectPoint(hand)) { this._target = null; return null; }

    const indexTip = joint(hand, "index-finger-tip").position;
    const indexDir = joint(hand, "index-finger-tip").position
      .subtract(joint(hand, "index-finger-phalanx-proximal").position)
      .normalize();

    const ray = new Ray(indexTip, indexDir, 5);
    const hit = scene.pickWithRay(ray);

    if (!hit?.pickedMesh) { this._target = null; return null; }
    if (hit.pickedMesh !== this._target) { this._target = hit.pickedMesh; this._dwellStart = now; }
    if (now - this._dwellStart >= this._requiredMs) return this._target;
    return null;
  }
}
```

---

## Calibration Guide

### Debug Overlay Setup

Display live joint distances in-headset (works in Quest browser):

```typescript
import { AdvancedDynamicTexture, TextBlock, StackPanel } from "@babylonjs/gui";

function createGestureDebugUI(scene: Scene): (data: Record<string, number>) => void {
  const ui = AdvancedDynamicTexture.CreateFullscreenUI("debug");
  const panel = new StackPanel();
  panel.horizontalAlignment = 0; // left
  panel.verticalAlignment = 0;   // top
  panel.width = "300px";
  ui.addControl(panel);

  const labels: Record<string, TextBlock> = {};

  return function update(data: Record<string, number>) {
    for (const [key, val] of Object.entries(data)) {
      if (!labels[key]) {
        const tb = new TextBlock(key);
        tb.color = "white"; tb.fontSize = 14; tb.height = "24px"; tb.textHorizontalAlignment = 0;
        panel.addControl(tb);
        labels[key] = tb;
      }
      labels[key].text = `${key}: ${val.toFixed(4)}`;
    }
  };
}

// Usage in render loop:
const updateDebug = createGestureDebugUI(scene);
scene.registerBeforeRender(() => {
  updateDebug({
    "thumb↔index": dist(hand, "thumb-tip", "index-finger-tip"),
    "indexBend":   fingerBend(hand, "index-finger"),
    "middleBend":  fingerBend(hand, "middle-finger"),
    "palmY":       getPalmNormal(hand).y,
  });
});
```

### Threshold Calibration Procedure

1. **Enter calibration mode** — disable all game logic
2. **For each gesture:**
   - Hold the pose for 3 seconds while logging the relevant distance/angle
   - Log the minimum value observed while performing it (`minDetect`)
   - Hold a non-gesture for 3 seconds, log max value (`maxNonDetect`)
3. **Set threshold = (minDetect + maxNonDetect) / 2**
4. **Add 10–15% margin** on the safe side
5. **Export to JSON:**

```json
{
  "pinch": { "threshold": 0.025, "unit": "meters" },
  "fistIndexBend": { "threshold": 0.60, "unit": "0-1 normalized" },
  "thumbsUpMinY": { "threshold": 0.05, "unit": "meters above wrist" }
}
```

### Common Calibration Issues

| Problem | Cause | Fix |
|---|---|---|
| Gesture fires when not intended | Threshold too loose | Raise threshold by 10–15% |
| Gesture never fires | Threshold too tight | Lower threshold |
| Flickers on/off | No debounce | Add `DebouncedGesture(4)` wrapper |
| Different results per user | Hand size variance | Use relative measurements (ratios, not absolute distances) |
| Works sitting, breaks standing | Wrist orientation differs | Use wrist-relative coordinates, not world-Y |

### Relative Distance (hand-size-agnostic)

Normalize distances by wrist-to-middle-metacarpal span (palm width):

```typescript
function getPalmScale(hand: WebXRHand): number {
  return dist(hand, "wrist", "middle-finger-metacarpal");
}

function normalizedDist(hand: WebXRHand, a: string, b: string): number {
  return dist(hand, a, b) / getPalmScale(hand);
}
// Now thresholds are hand-size independent: pinch < 0.3 (normalized) instead of 0.025m
```