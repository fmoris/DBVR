# Gesture Detection — Heurísticas y Articulaciones

> Para entender cómo la WebXR Hand Input API entrega estos datos como matrices de
> transformación en tiempo real, lee primero `references/webxr-api.md`.

## Articulaciones clave de WebXR Hand Input API

Babylon.js expone estas articulaciones via `WebXRHandJoint`:

```
WRIST
THUMB_TIP, THUMB_PHALANX_DISTAL
INDEX_FINGER_TIP, INDEX_FINGER_PHALANX_PROXIMAL
MIDDLE_FINGER_TIP, MIDDLE_FINGER_PHALANX_PROXIMAL
RING_FINGER_TIP
PINKY_TIP
```

## Heurística general de orientación de palma

```typescript
function getPalmDirection(hand: WebXRHand): Vector3 {
  const wrist  = hand.getJointMesh(WebXRHandJoint.WRIST);
  const middle = hand.getJointMesh(WebXRHandJoint.MIDDLE_FINGER_TIP);
  if (!wrist || !middle) return Vector3.Zero();
  return middle.absolutePosition.subtract(wrist.absolutePosition).normalize();
}

function getPalmNormal(hand: WebXRHand): Vector3 {
  // Producto cruzado índice → meñique para obtener normal de la palma
  const index = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP);
  const pinky = hand.getJointMesh(WebXRHandJoint.PINKY_TIP);
  const wrist = hand.getJointMesh(WebXRHandJoint.WRIST);
  if (!index || !pinky || !wrist) return Vector3.Zero();

  const toIndex = index.absolutePosition.subtract(wrist.absolutePosition);
  const toPinky = pinky.absolutePosition.subtract(wrist.absolutePosition);
  return Vector3.Cross(toIndex, toPinky).normalize();
}
```

## Detector: Kamehameha

**Condición**: ambas manos extendidas hacia la cámara (forward -Z en espacio XR), dedos juntos.

```typescript
function isKamehamehaHand(hand: WebXRHand, threshold: number): boolean {
  const palmDir = getPalmDirection(hand);
  const forward = new Vector3(0, 0, -1);

  // Palma apuntando hacia adelante
  const aligned = Vector3.Dot(palmDir, forward) > threshold;

  // Dedos juntos: distancia índice-meñique pequeña
  const indexTip = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP);
  const pinkyTip = hand.getJointMesh(WebXRHandJoint.PINKY_TIP);
  const spread = Vector3.Distance(
    indexTip!.absolutePosition,
    pinkyTip!.absolutePosition,
  );
  const togeter = spread < 0.06;

  return aligned && togeter;
}

// En el sistema: requiere AMBAS manos
function detectKamehameha(leftState, rightState, config): boolean {
  return (
    isKamehamehaHand(leftState.hand, config.alignmentThreshold) &&
    isKamehamehaHand(rightState.hand, config.alignmentThreshold)
  );
}
```

## Detector: Ki-Blast (una mano)

**Condición**: índice y medio extendidos apuntando (ángulo < 25°), anular y meñique recogidos.

```typescript
function isKiBlastGun(hand: WebXRHand): boolean {
  const wrist    = hand.getJointMesh(WebXRHandJoint.WRIST)!;
  const index    = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP)!;
  const middle   = hand.getJointMesh(WebXRHandJoint.MIDDLE_FINGER_TIP)!;
  const ring     = hand.getJointMesh(WebXRHandJoint.RING_FINGER_TIP)!;

  // Índice y medio extendidos (lejos de la muñeca)
  const indexExt = Vector3.Distance(index.absolutePosition, wrist.absolutePosition) > 0.12;
  const middleExt = Vector3.Distance(middle.absolutePosition, wrist.absolutePosition) > 0.10;

  // Anular recogido (cerca de la palma)
  const ringFolded = Vector3.Distance(ring.absolutePosition, wrist.absolutePosition) < 0.07;

  // Apuntando hacia adelante
  const gunDir = index.absolutePosition.subtract(wrist.absolutePosition).normalize();
  const forward = new Vector3(0, 0, -1);
  const pointing = Vector3.Dot(gunDir, forward) > 0.8;

  return indexExt && middleExt && ringFolded && pointing;
}
```

## Detector: Galick (gesto dinámico)

**Condición**: fase 1 = manos laterales con palmas hacia adentro; fase 2 = movimiento de empuje hacia adelante.

```typescript
interface GalickPhase { phase: 0 | 1 | 2; startZ: number; timer: number; }

function detectGalick(state: HandState & { galick: GalickPhase }): boolean {
  const wrist = state.hand.getJointMesh(WebXRHandJoint.WRIST)!;
  const palmNorm = getPalmNormal(state.hand);
  const inward = new Vector3(
    -Math.sign(wrist.absolutePosition.x), 0, 0,
  );
  const facingIn = Vector3.Dot(palmNorm, inward) > 0.7;
  const isLateral = Math.abs(wrist.absolutePosition.x) > 0.2;

  if (state.galick.phase === 0 && facingIn && isLateral) {
    state.galick.phase = 1;
    state.galick.startZ = wrist.absolutePosition.z;
    state.galick.timer = 0;
    return false;
  }

  if (state.galick.phase === 1) {
    state.galick.timer += scene.getEngine().getDeltaTime() / 1000;
    const pushed = wrist.absolutePosition.z < state.galick.startZ - 0.15; // avanzó 15cm
    if (pushed && state.galick.timer < 1.0) {
      state.galick.phase = 0;
      return true; // ¡GALICK detectado!
    }
    if (state.galick.timer > 1.5) state.galick.phase = 0; // timeout
  }
  return false;
}
```

## Detector: Genkidama (manos elevadas + reunión)

**Condición**: fase 1 = manos sobre la cabeza (y > 1.6m), palmas hacia arriba; fase 2 = bajar y reunir hacia adelante.

```typescript
function detectGenkidama(leftHand: WebXRHand, rightHand: WebXRHand): boolean {
  const lw = leftHand.getJointMesh(WebXRHandJoint.WRIST)!;
  const rw = rightHand.getJointMesh(WebXRHandJoint.WRIST)!;

  const lRaised = lw.absolutePosition.y > 1.6;
  const rRaised = rw.absolutePosition.y > 1.6;

  const lPalmUp = getPalmNormal(leftHand).y > 0.7;
  const rPalmUp = getPalmNormal(rightHand).y > 0.7;

  return lRaised && rRaised && lPalmUp && rPalmUp;
}
```

## Suavizado y filtro de ruido

Para evitar falsos positivos, usa un buffer circular de N frames:

```typescript
class FrameBuffer {
  private buffer: boolean[] = [];
  constructor(private size: number) {}

  push(value: boolean): boolean {
    this.buffer.push(value);
    if (this.buffer.length > this.size) this.buffer.shift();
    // Confirma solo si todos los frames recientes son true
    return this.buffer.length === this.size && this.buffer.every(Boolean);
  }

  reset(): void { this.buffer = []; }
}
```

## Calibración por nivel de skill

> **Fundamento teórico**: los umbrales de calibración están inspirados en los landmarks de
> MediaPipe Hands (*On-device Real-time Hand Tracking*), que define 21 puntos por mano con
> precisión de ±5mm en condiciones normales. El `confirmFrames` compensa la varianza del
> tracking en Meta Quest, donde la precisión puede bajar a ±15mm en movimientos rápidos.

| Nivel | `alignmentThreshold` | `confirmFrames` | Descripción |
|---|---|---|---|
| 1 | 0.75 | 15 | Muy permisivo, ideal para principiantes |
| 2 | 0.80 | 13 | Normal |
| 3 | 0.85 | 10 | Estándar competitivo |
| 4 | 0.88 | 8  | Preciso |
| 5 | 0.92 | 6  | Maestro del Ki — muy exigente |
