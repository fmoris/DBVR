# Árbol de Fases de Gestos — Dragon Ball Ki Attacks

---

## Extractores de features por nodo (dedos opcionales)

Cada nodo del árbol declara **qué extractor de features usa**. Esto permite que
la mayoría de fases trabajen solo con muñecas (liviano, rápido), y solo los nodos
que realmente necesitan distinguir configuraciones de dedos activen esa captura.

### El tipo FeatureExtractor

```typescript
// Contexto que se pasa a todos los extractores — contienen todos los datos disponibles
interface XRHandsContext {
  leftWrist:   BABYLON.AbstractMesh;
  rightWrist:  BABYLON.AbstractMesh;
  leftHand?:   BABYLON.WebXRHand;   // presente solo si hand tracking está activo
  rightHand?:  BABYLON.WebXRHand;   // presente solo si hand tracking está activo
  headPos:     BABYLON.Vector3;
  deltaTimeMs: number;              // ms desde el frame anterior
}

// Un extractor es simplemente una función pura que transforma el contexto en features
type FeatureExtractor = (ctx: XRHandsContext) => Float32Array | null;
```

### Extractores disponibles

```typescript
import { WebXRHandJoint } from '@babylonjs/core';

// ── EXTRACTOR 1: Solo muñecas (el más ligero) ──
// Usar en: idle, carga inicial, poses amplias
// Tamaño del vector: 17 valores
export const wristOnlyExtractor: FeatureExtractor = (ctx) => {
  const lp = ctx.leftWrist.absolutePosition;
  const rp = ctx.rightWrist.absolutePosition;
  const mid = lp.add(rp).scale(0.5);
  const lRel = lp.subtract(mid);
  const rRel = rp.subtract(mid);
  const dist = BABYLON.Vector3.Distance(lp, rp);
  const lH = lp.y - ctx.headPos.y;
  const rH = rp.y - ctx.headPos.y;

  // Velocidades usando deltaTime para ser frame-rate independent
  const dt = Math.max(ctx.deltaTimeMs, 1) / 1000;
  const lVel = lRel.length() / dt;
  const rVel = rRel.length() / dt;
  const lDir = lRel.normalize();
  const rDir = rRel.normalize();

  return new Float32Array([
    lRel.x, lRel.y, lRel.z,
    rRel.x, rRel.y, rRel.z,
    dist, lH, rH, lVel, rVel,
    lDir.x, lDir.y, lDir.z,
    rDir.x, rDir.y, rDir.z,
  ]);
};

// ── EXTRACTOR 2: Muñecas + tips de dedos ──
// Usar en: gestos que distinguen "mano abierta" vs "puño" vs "apuntar"
// Tamaño del vector: 17 + 30 = 47 valores
export const wristAndFingertipsExtractor: FeatureExtractor = (ctx) => {
  const base = wristOnlyExtractor(ctx);
  if (!base) return null;
  if (!ctx.leftHand || !ctx.rightHand) return null; // requiere hand tracking

  const fingerTips = [
    WebXRHandJoint.THUMB_TIP,
    WebXRHandJoint.INDEX_FINGER_TIP,
    WebXRHandJoint.MIDDLE_FINGER_TIP,
    WebXRHandJoint.RING_FINGER_TIP,
    WebXRHandJoint.PINKY_FINGER_TIP,
  ];

  const extras: number[] = [];
  for (const hand of [ctx.leftHand, ctx.rightHand]) {
    const wristPos = hand.getJointMesh(WebXRHandJoint.WRIST)?.absolutePosition;
    if (!wristPos) return null;
    for (const tip of fingerTips) {
      const mesh = hand.getJointMesh(tip);
      if (!mesh) { extras.push(0, 0, 0); continue; }
      const rel = mesh.absolutePosition.subtract(wristPos);
      // Normalizar por distancia de la muñeca para ser invariante a escala
      const scale = Math.max(rel.length(), 0.001);
      extras.push(rel.x / scale, rel.y / scale, rel.z / scale);
    }
  }

  // Combinar base + extras en un solo Float32Array
  const combined = new Float32Array(base.length + extras.length);
  combined.set(base, 0);
  combined.set(extras, base.length);
  return combined;
};

// ── EXTRACTOR 3: Solo dedos de una mano (para gestos sutiles) ──
// Usar en: ataques de una sola mano donde la forma de la mano importa
// Tamaño del vector: 15 valores (5 tips × 3 coords, relativas al wrist)
export const singleHandFingersExtractor = (handedness: 'left' | 'right'): FeatureExtractor =>
  (ctx) => {
    const hand = handedness === 'left' ? ctx.leftHand : ctx.rightHand;
    if (!hand) return null;

    const wristMesh = hand.getJointMesh(WebXRHandJoint.WRIST);
    if (!wristMesh) return null;
    const wristPos = wristMesh.absolutePosition;

    const tips = [
      WebXRHandJoint.THUMB_TIP,
      WebXRHandJoint.INDEX_FINGER_TIP,
      WebXRHandJoint.MIDDLE_FINGER_TIP,
      WebXRHandJoint.RING_FINGER_TIP,
      WebXRHandJoint.PINKY_FINGER_TIP,
    ];

    const features: number[] = [];
    for (const tip of tips) {
      const mesh = hand.getJointMesh(tip);
      if (!mesh) { features.push(0, 0, 0); continue; }
      const rel = mesh.absolutePosition.subtract(wristPos);
      const scale = Math.max(rel.length(), 0.001);
      features.push(rel.x / scale, rel.y / scale, rel.z / scale);
    }
    return new Float32Array(features);
  };

// ── EXTRACTOR 4: Combinado completo (máxima precisión, más costoso) ──
// Usar en: transformaciones (SSJ, etc.) donde todo el cuerpo importa
// Tamaño del vector: 17 + 30 + extras de orientación = ~53 valores
export const fullHandExtractor: FeatureExtractor = (ctx) => {
  const base = wristAndFingertipsExtractor(ctx);
  if (!base) return null;

  // Agregar orientación de ambas palmas (quaternion → 8 valores más)
  const lRot = ctx.leftWrist.absoluteRotationQuaternion;
  const rRot = ctx.rightWrist.absoluteRotationQuaternion;
  if (!lRot || !rRot) return base;

  const combined = new Float32Array(base.length + 8);
  combined.set(base, 0);
  combined.set([lRot.x, lRot.y, lRot.z, lRot.w, rRot.x, rRot.y, rRot.z, rRot.w], base.length);
  return combined;
};
```

### Matriz de elección de extractor por tipo de gesto

| Extractor | Tamaño | Cuándo usarlo |
|---|---|---|
| `wristOnlyExtractor` | 17 | Poses amplias: idle, carga inicial, posición de manos |
| `wristAndFingertipsExtractor` | 47 | Cuando importa si la mano está abierta o cerrada |
| `singleHandFingersExtractor` | 15 | Gestos de precisión de una sola mano |
| `fullHandExtractor` | ~53 | Transformaciones, gestos muy específicos y únicos |

> **Regla general**: empieza siempre con `wristOnlyExtractor`. Solo sube al siguiente
> nivel si el KNN de ese nodo no logra distinguir los labels con suficiente confianza.

---

## Concepto central: Gesture Phase Tree

Un **Gesture Phase Tree** es un árbol de decisión donde cada nodo es una fase
del gesto, y las ramas representan qué KNN clasifica en esa fase para determinar
el siguiente nodo. El camino recorrido desde la raíz hasta una hoja define el ataque.

```
                    [FASE 0: Idle]
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
    [FASE 1A: Manos juntas]   [FASE 1B: Mano alzada]
         (carga doble)            (carga simple)
              │                       │
       ┌──────┴──────┐         ┌──────┴──────┐
       ▼             ▼         ▼             ▼
  [FASE 2A:     [FASE 2B:  [FASE 2C:    [FASE 2D:
  Empuje        Brazos al   Empuje       Manos al
  frontal]      hombro]     lateral]     cielo]
       │             │         │             │
       ▼             ▼         ▼             ▼
 KAMEHAMEHA    GALICK GUN  KI BLAST     GENKIDAMA
```

**Clave**: El árbol permite que Kamehameha y Galick Gun compartan la fase 1A
(manos juntas) — el árbol no se compromete con ningún ataque hasta que el gesto
de la fase 2 lo desambigua.

---

## Arquitectura del sistema

### Tipos principales

```typescript
// Una fase es un nodo del árbol con su propio KNN y sus posibles ramas
interface GesturePhase {
  id: string;                              // ej: 'phase_1a_hands_together'
  label: string;                           // nombre humano: 'Manos Juntas'
  classifier: knnClassifier.KNNClassifier; // KNN propio de esta fase
  featureExtractor: FeatureExtractor;      // ← qué datos captura este nodo
  minHoldMs: number;                       // ms mínimo para confirmar la fase
  maxWaitMs: number;                       // ms máximo antes de timeout/reset
  confidenceThreshold: number;             // umbral de confianza para avanzar
  children: Map<string, GesturePhase>;     // ramas: label_clasificado → siguiente fase
  onEnter?: () => void;                    // callback al entrar (ej: efecto visual de carga)
  onExit?: () => void;                     // callback al salir
  onTimeout?: () => void;                  // callback si el jugador no completa la fase
}

// El ataque final (hoja del árbol)
interface KiAttack {
  id: string;           // 'kamehameha', 'ki_blast', etc.
  name: string;         // 'Kamehameha'
  execute: () => void;  // dispara el ataque en el juego
}

// Estado actual del árbol
interface PhaseTreeState {
  currentPhase: GesturePhase;
  phaseStartTime: number;       // timestamp de entrada a la fase actual
  phaseHoldTime: number;        // ms que lleva sosteniendo la fase actual
  path: string[];               // historial de fases recorridas (para debug)
}
```

---

## Implementación del PhaseTreeManager

```typescript
import * as tf from '@tensorflow/tfjs';
import * as knnClassifier from '@tensorflow-models/knn-classifier';
import * as BABYLON from '@babylonjs/core';

export class PhaseTreeManager {
  private state: PhaseTreeState;
  private rootPhase: GesturePhase;
  private attacks: Map<string, KiAttack>;
  private isBusy = false;

  constructor(rootPhase: GesturePhase, attacks: Map<string, KiAttack>) {
    this.rootPhase = rootPhase;
    this.attacks = attacks;
    this.reset();
  }

  reset() {
    this.state = {
      currentPhase: this.rootPhase,
      phaseStartTime: performance.now(),
      phaseHoldTime: 0,
      path: [this.rootPhase.id]
    };
    this.rootPhase.onEnter?.();
  }

  /**
   * Llamar cada frame con el contexto XR completo.
   * El nodo actual elige qué extractor usar — el caller no necesita saber cuál.
   * Retorna el nombre del ataque disparado, o null si aún en progreso.
   */
  async update(ctx: XRHandsContext): Promise<string | null> {
    if (this.isBusy) return null;

    const phase = this.state.currentPhase;
    const now = performance.now();
    const elapsed = now - this.state.phaseStartTime;

    // ── Timeout ──
    if (elapsed > phase.maxWaitMs) {
      console.log(`[PhaseTree] Timeout en "${phase.id}" tras ${elapsed.toFixed(0)}ms`);
      phase.onTimeout?.();
      this.reset();
      return null;
    }

    // ── Extraer features usando el extractor PROPIO DE ESTE NODO ──
    const features = phase.featureExtractor(ctx);
    if (!features) return null; // hand tracking no disponible aún

    if (phase.classifier.getNumClasses() === 0) return null;

    this.isBusy = true;
    const tensor = tf.tensor1d(features);
    let label = 'none';
    let confidence = 0;

    try {
      const result = await phase.classifier.predictClass(tensor, 3);
      label = result.label;
      confidence = result.confidences[label] ?? 0;
    } finally {
      tensor.dispose();
      this.isBusy = false;
    }

    if (confidence < phase.confidenceThreshold) return null;

    this.state.phaseHoldTime += ctx.deltaTimeMs;
    if (this.state.phaseHoldTime < phase.minHoldMs) return null;

    // ── Buscar rama ──
    const nextPhase = phase.children.get(label);
    if (!nextPhase) {
      this.reset();
      return null;
    }

    // ── Hoja: disparar ataque ──
    if (nextPhase.children.size === 0) {
      const attack = this.attacks.get(nextPhase.id);
      const attackName = attack?.name ?? nextPhase.id;
      console.log(`[PhaseTree] ✅ ${attackName} | ${[...this.state.path, nextPhase.id].join(' → ')}`);
      attack?.execute();
      this.reset();
      return attackName;
    }

    // ── Avanzar al siguiente nodo ──
    phase.onExit?.();
    this.state.path.push(nextPhase.id);
    this.state.currentPhase = nextPhase;
    this.state.phaseStartTime = performance.now();
    this.state.phaseHoldTime = 0;
    nextPhase.onEnter?.();

    // ── Cambio de extractor: loguear si cambia entre nodos ──
    if (nextPhase.featureExtractor !== phase.featureExtractor) {
      console.log(`[PhaseTree] 🔄 Extractor cambia en "${nextPhase.id}": ${nextPhase.featureExtractor.name}`);
    }

    return null;
  }
}
```

---

## Feature extractor para Ki (posición de palmas, sin dedos)

Para Dragon Ball, las features importantes son:
- Posición 3D de cada muñeca (wrist) en el espacio del jugador
- Distancia entre manos
- Velocidad de movimiento (delta entre frames)
- Altura relativa de las manos respecto a la cabeza

```typescript
// Cache del frame anterior para calcular velocidades
let prevLeftPos = BABYLON.Vector3.Zero();
let prevRightPos = BABYLON.Vector3.Zero();

export function extractKiFeatures(
  leftWrist: BABYLON.AbstractMesh,
  rightWrist: BABYLON.AbstractMesh,
  headPos: BABYLON.Vector3   // posición de la cámara XR (cabeza del jugador)
): Float32Array {
  const lp = leftWrist.absolutePosition;
  const rp = rightWrist.absolutePosition;

  // Punto medio entre las manos (referencia relativa al jugador)
  const mid = lp.add(rp).scale(0.5);

  // Posiciones relativas al midpoint (elimina traslación global)
  const lRel = lp.subtract(mid);
  const rRel = rp.subtract(mid);

  // Distancia entre manos
  const dist = BABYLON.Vector3.Distance(lp, rp);

  // Altura relativa a la cabeza (normalizada)
  const lHeight = (lp.y - headPos.y); // negativo = manos abajo, positivo = arriba
  const rHeight = (rp.y - headPos.y);

  // Velocidad (delta posición desde frame anterior)
  const lVel = lp.subtract(prevLeftPos).length();
  const rVel = rp.subtract(prevRightPos).length();

  // Dirección del movimiento (normalizada)
  const lDir = lp.subtract(prevLeftPos).normalize();
  const rDir = rp.subtract(prevRightPos).normalize();

  prevLeftPos = lp.clone();
  prevRightPos = rp.clone();

  return new Float32Array([
    // Posiciones relativas (6 valores)
    lRel.x, lRel.y, lRel.z,
    rRel.x, rRel.y, rRel.z,
    // Distancia entre manos (1 valor)
    dist,
    // Alturas relativas a la cabeza (2 valores)
    lHeight, rHeight,
    // Velocidades (2 valores)
    lVel, rVel,
    // Direcciones de movimiento (6 valores)
    lDir.x, lDir.y, lDir.z,
    rDir.x, rDir.y, rDir.z,
  ]);
  // Total: 17 valores — liviano y discriminativo para Ki attacks
}
```

---

## Definición del árbol Dragon Ball completo

```typescript
import * as knnClassifier from '@tensorflow-models/knn-classifier';

function makePhase(config: Partial<GesturePhase> & { id: string; featureExtractor: FeatureExtractor }): GesturePhase {
  return {
    label: config.id,
    classifier: knnClassifier.create(),
    minHoldMs: 300,
    maxWaitMs: 3000,
    confidenceThreshold: 0.70,
    children: new Map(),
    ...config,
  };
}

export function buildDragonBallTree(): { root: GesturePhase, attacks: Map<string, KiAttack> } {

  // ── HOJAS (ataques finales) ──
  // Las hojas no necesitan extractor porque nunca clasifican — solo ejecutan
  const kamehamehaLeaf  = makePhase({ id: 'kamehameha',  featureExtractor: wristOnlyExtractor });
  const galickLeaf      = makePhase({ id: 'galick_gun',  featureExtractor: wristOnlyExtractor });
  const kiBlastLeaf     = makePhase({ id: 'ki_blast',    featureExtractor: wristOnlyExtractor });
  const genkidamaLeaf   = makePhase({ id: 'genkidama',   featureExtractor: wristOnlyExtractor });
  const flashLeaf       = makePhase({ id: 'final_flash', featureExtractor: wristOnlyExtractor });

  // ── FASE 2A: Tipo de empuje con dos manos ──
  // Solo necesita muñecas: distingue "manos van al frente" vs "manos van al hombro"
  const phase2A = makePhase({
    id: 'phase_2a_push',
    label: 'Tipo de empuje',
    featureExtractor: wristOnlyExtractor,   // ← solo muñecas, no necesita dedos
    minHoldMs: 200,
    maxWaitMs: 2500,
    confidenceThreshold: 0.72,
    onEnter: () => console.log('⚡ Define dirección del empuje...'),
  });
  phase2A.children.set('push_forward',  kamehamehaLeaf);
  phase2A.children.set('push_shoulder', galickLeaf);

  // ── FASE 2B: Tipo de ataque de una mano ──
  // Aquí SÍ importa la forma de la mano:
  //   Ki Blast   → mano abierta empujando rápido
  //   Genkidama  → palma hacia arriba (abierta)
  //   Final Flash → dedos juntos cargando
  // Por eso usa wristAndFingertipsExtractor
  const phase2B = makePhase({
    id: 'phase_2b_single_hand',
    label: 'Tipo de ataque simple',
    featureExtractor: wristAndFingertipsExtractor,  // ← activa captura de dedos
    minHoldMs: 150,
    maxWaitMs: 2000,
    confidenceThreshold: 0.68,
    onEnter: () => console.log('⚡ Define tipo de ataque — forma de mano importa...'),
  });
  phase2B.children.set('push_fast_open',   kiBlastLeaf);
  phase2B.children.set('palm_up_open',     genkidamaLeaf);
  phase2B.children.set('fingers_together', flashLeaf);

  // ── FASE 1: Carga — distingue doble mano vs una mano ──
  // Solo posición de muñecas: ¿están juntas o separadas?
  const phase1 = makePhase({
    id: 'phase_1_charge',
    label: 'Tipo de carga',
    featureExtractor: wristOnlyExtractor,   // ← solo muñecas
    minHoldMs: 400,
    maxWaitMs: 5000,
    confidenceThreshold: 0.75,
    onEnter: () => console.log('🔥 Carga de ki detectada...'),
    onTimeout: () => console.log('❌ Carga cancelada'),
  });
  phase1.children.set('hands_together',     phase2A);
  phase1.children.set('single_hand_raised', phase2B);

  // ── FASE 0: Idle ──
  // Solo muñecas: ¿hay movimiento de carga o no?
  const phase0 = makePhase({
    id: 'phase_0_idle',
    label: 'Idle',
    featureExtractor: wristOnlyExtractor,
    minHoldMs: 100,
    maxWaitMs: Infinity,
    confidenceThreshold: 0.65,
  });
  phase0.children.set('ki_charge_start', phase1);

  const attacks = new Map<string, KiAttack>([
    ['kamehameha',  { id: 'kamehameha',  name: 'Kamehameha',  execute: () => fireKamehameha()  }],
    ['galick_gun',  { id: 'galick_gun',  name: 'Galick Gun',  execute: () => fireGalickGun()   }],
    ['ki_blast',    { id: 'ki_blast',    name: 'Ki Blast',    execute: () => fireKiBlast()     }],
    ['genkidama',   { id: 'genkidama',   name: 'Genkidama',   execute: () => chargeGenkidama() }],
    ['final_flash', { id: 'final_flash', name: 'Final Flash', execute: () => fireFinalFlash()  }],
  ]);

  return { root: phase0, attacks };
}
```

### Mapa visual de extractores por nodo

```
[IDLE]          → wristOnly         (¿hay movimiento de carga?)
   │
[CARGA F1]      → wristOnly         (¿manos juntas o separadas?)
   │
   ├─[EMPUJE F2A] → wristOnly       (¿hacia dónde empujan las manos?)
   │     ├─ KAMEHAMEHA
   │     └─ GALICK GUN
   │
   └─[SIMPLE F2B] → wrist+fingertips ← 🖐 AQUÍ SE ACTIVAN LOS DEDOS
         ├─ KI BLAST    (mano abierta, empuje rápido)
         ├─ GENKIDAMA   (palma hacia arriba)
         └─ FINAL FLASH (dedos juntos)
```

Los dedos solo se capturan en `phase_2b_single_hand` porque es el único nodo donde
la **forma de la mano** cambia el significado del gesto. En todos los demás nodos
la posición global de las manos es suficiente.

---

## Entrenamiento del árbol (por nodo)

Cada nodo tiene su propio KNN y su propio extractor. Al entrenar, **usas el extractor
del nodo** para que los ejemplos de entrenamiento tengan el mismo formato que los
de inferencia. Si un nodo usa `wristAndFingertipsExtractor`, sus ejemplos de
entrenamiento también deben venir de ese extractor.

```typescript
/**
 * Entrena un nodo específico del árbol capturando N frames.
 * Usa el featureExtractor propio del nodo automáticamente.
 */
async function trainPhaseNode(
  phase: GesturePhase,
  label: string,
  ctx: XRHandsContext,
  frames: number = 20,
  intervalMs: number = 100
): Promise<void> {
  return new Promise((resolve) => {
    let count = 0;
    const interval = setInterval(() => {
      // El nodo extrae sus propias features — mismo extractor que en inferencia
      const features = phase.featureExtractor(ctx);
      if (features) {
        const tensor = tf.tensor1d(features);
        phase.classifier.addExample(tensor, label);
        tensor.dispose();
      }
      count++;
      if (count >= frames) {
        clearInterval(interval);
        console.log(`[Train] Nodo "${phase.id}", label "${label}": ${count} ejemplos añadidos`);
        resolve();
      }
    }, intervalMs);
  });
}

// Ejemplo de sesión de entrenamiento completa para el árbol Dragon Ball:
async function runTrainingSession(tree: ReturnType<typeof buildDragonBallTree>, ctx: XRHandsContext) {
  const { root } = tree;
  const phase1 = root.children.get('ki_charge_start')!;
  const phase2A = phase1.children.get('hands_together')!;
  const phase2B = phase1.children.get('single_hand_raised')!;

  console.log('== ENTRENAMIENTO: Fase 0 (Idle) ==');
  console.log('Mantén las manos relajadas...');
  await trainPhaseNode(root, 'idle', ctx, 20);
  console.log('Inicia movimiento de carga...');
  await trainPhaseNode(root, 'ki_charge_start', ctx, 20);

  console.log('== ENTRENAMIENTO: Fase 1 (Carga) ==');
  // phase1 usa wristOnlyExtractor → no necesita hand tracking
  console.log('Junta ambas manos (postura Kamehameha)...');
  await trainPhaseNode(phase1, 'hands_together', ctx, 20);
  console.log('Levanta una sola mano...');
  await trainPhaseNode(phase1, 'single_hand_raised', ctx, 20);

  console.log('== ENTRENAMIENTO: Fase 2A (Empuje doble) ==');
  // phase2A usa wristOnlyExtractor → no necesita hand tracking
  console.log('Empuja las manos hacia el frente...');
  await trainPhaseNode(phase2A, 'push_forward', ctx, 15);
  console.log('Empuja las manos hacia el hombro (Galick Gun)...');
  await trainPhaseNode(phase2A, 'push_shoulder', ctx, 15);

  console.log('== ENTRENAMIENTO: Fase 2B (Ataque simple) ==');
  // phase2B usa wristAndFingertipsExtractor → SÍ necesita hand tracking
  // Si ctx.leftHand/rightHand son undefined, trainPhaseNode fallará silenciosamente
  console.log('Empuja con mano abierta (Ki Blast)...');
  await trainPhaseNode(phase2B, 'push_fast_open', ctx, 15);
  console.log('Levanta palma hacia arriba (Genkidama)...');
  await trainPhaseNode(phase2B, 'palm_up_open', ctx, 15);
  console.log('Junta dedos y carga al frente (Final Flash)...');
  await trainPhaseNode(phase2B, 'fingers_together', ctx, 15);

  console.log('✅ Entrenamiento completo');
}

---

## Integración en el game loop

```typescript
const { root, attacks } = buildDragonBallTree();
const phaseTree = new PhaseTreeManager(root, attacks);

let prevFrameTime = performance.now();

scene.registerAfterRender(async () => {
  const leftWrist  = handTracking.left?.hand.getJointMesh(WebXRHandJoint.WRIST);
  const rightWrist = handTracking.right?.hand.getJointMesh(WebXRHandJoint.WRIST);
  const headPos    = xr.baseExperience.camera.position;
  const now        = performance.now();

  if (!leftWrist || !rightWrist) return;

  // Construir el contexto una vez por frame — cada nodo toma lo que necesita
  const ctx: XRHandsContext = {
    leftWrist,
    rightWrist,
    leftHand:   handTracking.left?.hand,   // puede ser undefined si no hay hand tracking
    rightHand:  handTracking.right?.hand,
    headPos,
    deltaTimeMs: now - prevFrameTime,
  };
  prevFrameTime = now;

  const attack = await phaseTree.update(ctx);
  if (attack) {
    console.log(`🐉 ¡${attack}!`);
  }
});
```

> **Nota**: El caller construye el `XRHandsContext` con **todos** los datos disponibles
> (incluyendo `leftHand` y `rightHand` con los dedos). Cada nodo del árbol decide
> internamente cuánto de ese contexto usa a través de su `featureExtractor`.
> Pasar datos extra no tiene costo — el extractor simplemente los ignora si no los necesita.

---

## Visualización del estado del árbol (debug)

```typescript
import { AdvancedDynamicTexture, TextBlock } from '@babylonjs/gui';

export function setupPhaseTreeDebugUI(phaseTree: PhaseTreeManager, scene: BABYLON.Scene) {
  const ui = AdvancedDynamicTexture.CreateFullscreenUI('PhaseDebug');
  const text = new TextBlock('phaseText');
  text.color = 'yellow';
  text.fontSize = 20;
  text.textVerticalAlignment = BABYLON.GUI.Control.VERTICAL_ALIGNMENT_TOP;
  ui.addControl(text);

  scene.registerAfterRender(() => {
    const s = phaseTree.state;
    const hold = (s.phaseHoldTime / s.currentPhase.minHoldMs * 100).toFixed(0);
    text.text = [
      `Fase: ${s.currentPhase.label}`,
      `Carga: ${hold}%`,
      `Path: ${s.path.join(' → ')}`,
      `Tiempo en fase: ${(performance.now() - s.phaseStartTime).toFixed(0)}ms`,
    ].join('\n');
  });
}
```

---

## Diagrama de estados por ataque

### Kamehameha
```
Idle → [ki_charge_start] → Carga doble
     → [hands_together]  → Tipo de empuje
     → [push_forward]    → 💥 KAMEHAMEHA
```

### Ki Blast
```
Idle → [ki_charge_start]    → Carga doble
     → [single_hand_raised] → Ataque simple
     → [push_fast]          → 💥 KI BLAST
```

### Genkidama
```
Idle → [ki_charge_start]    → Carga doble
     → [single_hand_raised] → Ataque simple
     → [raise_up]           → 💥 GENKIDAMA
```

---

## Tuning de parámetros por fase

| Fase         | minHoldMs | maxWaitMs | threshold | Razón                                      |
|--------------|-----------|-----------|-----------|---------------------------------------------|
| Idle         | 100       | ∞         | 0.65      | Detección rápida, falsos positivos OK       |
| Carga (F1)   | 400       | 5000      | 0.75      | La carga es lenta e intencional             |
| Dirección (F2A)| 200     | 2500      | 0.72      | Movimiento rápido pero preciso              |
| Single (F2B) | 150       | 2000      | 0.68      | Ki Blast es rápido, no puede ser muy lento  |

---

## Consideraciones de diseño

**¿Por qué un KNN por nodo y no uno global?**
Porque las features que distinguen "manos juntas vs mano alzada" (Fase 1) son
completamente distintas a las que distinguen "empuje frontal vs empuje lateral" (Fase 2A).
Un único KNN intentaría clasificar todos los casos a la vez, mezclando features de
contextos distintos y reduciendo la precisión.

**¿Qué pasa si el jugador se confunde de gesto?**
El `maxWaitMs` de cada fase resetea automáticamente el árbol. El jugador simplemente
hace una pausa y vuelve a empezar desde idle. No hay penalización, el árbol es
tolerante a errores.

**¿Se puede agregar más ataques fácilmente?**
Sí. Solo necesitas: (1) crear la hoja con el nuevo ID, (2) agregar el label al
KNN del nodo padre, (3) registrar el ataque en el Map de attacks. El árbol
se extiende sin modificar la lógica del `PhaseTreeManager`.