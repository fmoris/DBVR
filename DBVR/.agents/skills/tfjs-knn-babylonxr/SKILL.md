---
name: tfjs-knn-babylonxr
description: >
  Implementa clasificación KNN con TensorFlow.js integrada en juegos y experiencias
  construidas con Babylon.js y WebXR. Usa este skill SIEMPRE que el usuario quiera:
  - Clasificar gestos de manos o cuerpo en tiempo real dentro de una escena Babylon.js/WebXR
  - Usar KNN de TensorFlow.js para reconocer acciones del jugador (gestos, posturas, movimientos de controladores)
  - Integrar ML de clasificación como mecánica de juego en experiencias VR/XR del navegador
  - Entrenar on-the-fly un clasificador KNN con datos provenientes de hand tracking o input XR
  - Detectar combos, hechizos, poses o comandos en juegos WebXR sin servidor de ML
  Trigger inmediato si el usuario menciona: "KNN", "clasificar gestos VR", "tensorflow babylon",
  "reconocimiento de acciones WebXR", "classifier game input", "pose detection babylon",
  "tfjs knn webxr", o cualquier combinación de clasificación ML + juego + WebXR/VR/Babylon.
---

# TensorFlow.js KNN + Babylon.js WebXR — Skill

Guía completa para integrar un clasificador KNN (K-Nearest Neighbors) de TensorFlow.js
como sistema de input inteligente en juegos y experiencias WebXR construidos con Babylon.js.

---

## Arquitectura general

```
[WebXR Hand/Controller Input]
        │
        ▼
[Extracción de features]   ← posiciones de joints, ángulos, distancias
        │
        ▼
[TF.js KNN Classifier]     ← addExample() / predictClass()
        │
        ▼
[Babylon.js Game Logic]    ← dispara eventos, animaciones, efectos
```

El clasificador KNN **no requiere entrenamiento previo** ni modelo externo: aprende
en tiempo de ejecución a partir de ejemplos etiquetados. Es ideal para gestos XR porque:
- Funciona con vectores de features extraídas de joints 3D.
- Permite re-entrenar on-the-fly dentro de la sesión VR.
- No necesita GPU pesada: el backend WASM o WebGL de TFJS es suficiente.

---

## 1. Setup del proyecto (Vite + TypeScript)

```bash
npm create vite@latest my-xr-game -- --template vanilla-ts
cd my-xr-game
npm install @babylonjs/core @babylonjs/loaders
npm install @tensorflow/tfjs @tensorflow-models/knn-classifier
```

> **HTTPS obligatorio** para WebXR. Configura `vite.config.ts`:
```ts
import { defineConfig } from 'vite';
export default defineConfig({
  server: { https: true, port: 3443 }
});
```

---

## 2. Inicializar Babylon.js + WebXR con Hand Tracking

```typescript
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders/glTF';

export async function initScene(canvas: HTMLCanvasElement) {
  const engine = new BABYLON.Engine(canvas, true);
  const scene = new BABYLON.Scene(engine);

  new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene);

  // Cámara de respaldo (para desktop)
  const camera = new BABYLON.FreeCamera('cam', new BABYLON.Vector3(0, 1.6, -3), scene);
  camera.setTarget(BABYLON.Vector3.Zero());

  // XR Experience con Hand Tracking
  const xr = await scene.createDefaultXRExperienceAsync({
    floorMeshes: [], // agrega meshes de suelo si tienes
    uiOptions: { sessionMode: 'immersive-vr' }
  });

  // Habilitar hand tracking
  const handTracking = await xr.baseExperience.featuresManager.enableFeature(
    BABYLON.WebXRFeatureName.HAND_TRACKING,
    'latest',
    {
      xrInput: xr.input,
      jointMeshes: { invisible: true } // joints invisibles, solo datos
    }
  ) as BABYLON.WebXRHandTracking;

  engine.runRenderLoop(() => scene.render());
  window.addEventListener('resize', () => engine.resize());

  return { scene, xr, handTracking };
}
```

---

## 3. Inicializar el clasificador KNN

```typescript
import * as tf from '@tensorflow/tfjs';
import * as knnClassifier from '@tensorflow-models/knn-classifier';

// Seleccionar backend: 'webgl' (GPU) o 'wasm' (más estable en Quest)
await tf.setBackend('webgl');
await tf.ready();

const classifier = knnClassifier.create();
```

> **Nota de backend**: En Meta Quest Browser, `webgl` funciona bien. Si hay inestabilidad, cambia a `wasm`:
> ```ts
> import '@tensorflow/tfjs-backend-wasm';
> await tf.setBackend('wasm');
> ```

---

## 4. Extraer features desde joints de las manos

Los joints de WebXR siguen el estándar W3C: 25 joints por mano (índice 0 = wrist, 1-4 = pulgar, etc.).

```typescript
import { WebXRHandJoint } from '@babylonjs/core';

/**
 * Extrae un vector de features normalizado desde una mano WebXR.
 * Devuelve un Float32Array con distancias y ángulos clave.
 */
export function extractHandFeatures(hand: BABYLON.WebXRHand): Float32Array | null {
  const wrist = hand.getJointMesh(WebXRHandJoint.WRIST);
  if (!wrist) return null;

  const wristPos = wrist.absolutePosition;
  const features: number[] = [];

  // Joints relevantes (tip de cada dedo + metacarpianos)
  const relevantJoints = [
    WebXRHandJoint.THUMB_TIP,
    WebXRHandJoint.INDEX_FINGER_TIP,
    WebXRHandJoint.MIDDLE_FINGER_TIP,
    WebXRHandJoint.RING_FINGER_TIP,
    WebXRHandJoint.PINKY_FINGER_TIP,
    WebXRHandJoint.INDEX_FINGER_METACARPAL,
    WebXRHandJoint.MIDDLE_FINGER_METACARPAL,
    WebXRHandJoint.RING_FINGER_METACARPAL,
    WebXRHandJoint.PINKY_FINGER_METACARPAL,
  ];

  for (const jointId of relevantJoints) {
    const joint = hand.getJointMesh(jointId);
    if (!joint) { features.push(0, 0, 0); continue; }
    // Posición relativa al wrist (invariante a la posición del jugador)
    const rel = joint.absolutePosition.subtract(wristPos);
    features.push(rel.x, rel.y, rel.z);
  }

  // Normalizar por la distancia máxima (invariante a escala de mano)
  const maxDist = Math.max(...features.map(Math.abs), 0.001);
  return new Float32Array(features.map(f => f / maxDist));
}
```

### Feature engineering para controladores XR (sin hand tracking)

```typescript
export function extractControllerFeatures(
  leftPos: BABYLON.Vector3,
  rightPos: BABYLON.Vector3,
  leftRot: BABYLON.Quaternion,
  rightRot: BABYLON.Quaternion
): Float32Array {
  const midpoint = leftPos.add(rightPos).scale(0.5);
  const dist = BABYLON.Vector3.Distance(leftPos, rightPos);
  return new Float32Array([
    // Posiciones relativas al midpoint
    leftPos.x - midpoint.x, leftPos.y - midpoint.y, leftPos.z - midpoint.z,
    rightPos.x - midpoint.x, rightPos.y - midpoint.y, rightPos.z - midpoint.z,
    // Distancia entre manos (normalizada)
    dist,
    // Componentes de rotación
    leftRot.x, leftRot.y, leftRot.z, leftRot.w,
    rightRot.x, rightRot.y, rightRot.z, rightRot.w,
  ]);
}
```

---

## 5. Entrenar el clasificador (añadir ejemplos)

```typescript
/**
 * Captura N frames de la postura actual y los añade como ejemplos de la clase `label`.
 * Llama a esto cuando el jugador hace el gesto correcto (botón de entrenamiento en UI).
 */
export async function trainGesture(
  hand: BABYLON.WebXRHand,
  label: string,
  frames: number = 20,
  intervalMs: number = 100
): Promise<void> {
  return new Promise((resolve) => {
    let count = 0;
    const interval = setInterval(() => {
      const features = extractHandFeatures(hand);
      if (features) {
        const tensor = tf.tensor1d(features);
        classifier.addExample(tensor, label);
        tensor.dispose(); // Liberar memoria WebGL
      }
      count++;
      if (count >= frames) {
        clearInterval(interval);
        resolve();
      }
    }, intervalMs);
  });
}
```

> **Tip**: Añade 15–30 ejemplos por clase. Con 3 gestos y 20 frames cada uno, el clasificador
> tarda < 100ms en inicializarse. No bloquea el render loop.

---

## 6. Clasificar en el game loop

```typescript
// Estado compartido (evitar llamadas simultáneas)
let isClassifying = false;
let lastLabel = 'none';
let lastConfidence = 0;

export async function classifyGesture(hand: BABYLON.WebXRHand): Promise<string> {
  if (isClassifying || classifier.getNumClasses() === 0) return lastLabel;
  
  const features = extractHandFeatures(hand);
  if (!features) return lastLabel;

  isClassifying = true;
  const tensor = tf.tensor1d(features);

  try {
    const result = await classifier.predictClass(tensor, 3); // k=3
    lastLabel = result.label;
    lastConfidence = result.confidences[result.label] ?? 0;
  } finally {
    tensor.dispose();
    isClassifying = false;
  }

  return lastLabel;
}

// En el render loop de Babylon.js:
scene.registerAfterRender(async () => {
  if (!handTracking || !handTracking.left) return;
  const gesture = await classifyGesture(handTracking.left.hand);
  
  if (lastConfidence > 0.7) { // umbral de confianza
    handleGameAction(gesture);
  }
});
```

---

## 7. Mapear gestos a acciones de juego

```typescript
const GESTURE_ACTIONS: Record<string, () => void> = {
  'fist':      () => gameState.player.punch(),
  'open_hand': () => gameState.player.shield(),
  'point':     () => gameState.player.shoot(),
  'pinch':     () => gameState.player.grab(),
  'thumbs_up': () => gameState.ui.confirm(),
};

function handleGameAction(gesture: string) {
  const action = GESTURE_ACTIONS[gesture];
  if (action) action();
}
```

---

## 8. Persistir y restaurar el modelo KNN

```typescript
// Guardar dataset entrenado en localStorage
export function saveClassifier() {
  const dataset = classifier.getClassifierDataset();
  const serialized: Record<string, number[][]> = {};
  for (const [label, tensor] of Object.entries(dataset)) {
    serialized[label] = Array.from(tensor.arraySync() as number[][]);
  }
  localStorage.setItem('knn_dataset', JSON.stringify(serialized));
}

// Restaurar dataset guardado
export async function loadClassifier() {
  const raw = localStorage.getItem('knn_dataset');
  if (!raw) return;
  const parsed = JSON.parse(raw) as Record<string, number[][]>;
  const dataset: Record<string, tf.Tensor2D> = {};
  for (const [label, data] of Object.entries(parsed)) {
    dataset[label] = tf.tensor2d(data);
  }
  classifier.setClassifierDataset(dataset);
}
```

---

## 9. Gestión de memoria — reglas críticas

> TensorFlow.js con backend WebGL **no tiene garbage collection automático** para tensores.
> Olvidar `dispose()` causa memory leaks que degradan el FPS en el game loop.

```typescript
// ✅ CORRECTO: siempre disponer tensores
const t = tf.tensor1d(features);
const result = await classifier.predictClass(t, 3);
t.dispose(); // ← OBLIGATORIO

// ✅ CORRECTO: usar tf.tidy() para operaciones intermedias
const result2 = await tf.tidy(() => {
  const t2 = tf.tensor1d(features);
  return classifier.predictClass(t2, 3); // t2 se dispone automáticamente
});

// ❌ INCORRECTO: tensor sin dispose → memory leak
const t3 = tf.tensor1d(features);
classifier.predictClass(t3, 3); // t3 perdido → leak
```

---

## 10. Patrones de uso por tipo de juego

### Juego de combate (reconocimiento de golpes)
- Features: distancias pulgar-dedos, velocidad angular de muñeca, posición relativa de ambas manos.
- Clases: `jab`, `hook`, `uppercut`, `block`, `dodge`.
- k = 3, umbral de confianza: 0.65.

### Juego de hechizos / magia
- Features: posición 3D de los 5 dedos, ángulo del wrist.
- Clases: `fireball`, `shield`, `heal`, `teleport`.
- k = 5, umbral: 0.75 (hechizos requieren mayor certeza).

### Juego de ritmo / música
- Features: velocidad de movimiento de manos (delta posición entre frames), posición Y relativa.
- Clases: `beat_left`, `beat_right`, `hold`, `rest`.
- k = 1 (respuesta rápida), umbral: 0.60.

### Juego de puzzles / interacción con objetos
- Features: estado de pinza (distancia index-thumb), orientación de la palma.
- Clases: `grip`, `release`, `rotate_cw`, `rotate_ccw`.
- k = 3, umbral: 0.70.

---

## 10B. Gestos de Ki — Ataques con árbol de fases (Dragon Ball)

Para juegos donde varios ataques **comparten gestos iniciales** (ej: Kamehameha y
Galick Gun ambos empiezan con manos juntas), un único KNN global no funciona bien
porque intenta resolver toda la ambigüedad en un solo paso.

La solución es un **Gesture Phase Tree**: un árbol donde cada nodo tiene su propio
KNN especializado, y el camino recorrido define el ataque.

### ¿Por qué árbol y no un solo KNN?

| Enfoque | Problema |
|---|---|
| KNN único global | Confunde "manos juntas antes de Kamehameha" con "manos juntas antes de Galick" porque las features de fase 1 son idénticas |
| Árbol de fases | Cada nodo solo clasifica lo que importa EN ESA FASE — la ambigüedad se resuelve progresivamente |

### Árbol para ataques Dragon Ball

```
[IDLE]
   │
   └─ ki_charge_start ──► [FASE 1: CARGA]
                               │
                ┌──────────────┴──────────────┐
                ▼                             ▼
       hands_together               single_hand_raised
                │                             │
       [FASE 2A: EMPUJE]           [FASE 2B: ATAQUE SIMPLE]
          │           │              │         │         │
    push_forward  push_shoulder  push_fast  raise_up  charge_fwd
          │           │              │         │         │
    KAMEHAMEHA   GALICK GUN      KI BLAST  GENKIDAMA  FINAL FLASH
```

### Features para Ki (sin necesitar dedos)

Para Ki attacks solo necesitas la **posición y movimiento de las muñecas**,
no los 25 joints de los dedos. El vector de features tiene 17 valores:

```
[ lRel.x, lRel.y, lRel.z,    // posición mano izq relativa al midpoint
  rRel.x, rRel.y, rRel.z,    // posición mano der relativa al midpoint
  distancia_entre_manos,      // qué tan separadas están
  alturaIzq, alturaDer,       // altura relativa a la cabeza del jugador
  velIzq, velDer,             // velocidad de cada mano (magnitud)
  lDir.x, lDir.y, lDir.z,    // dirección de movimiento mano izq
  rDir.x, rDir.y, rDir.z ]   // dirección de movimiento mano der
```

### Labels que entrena cada nodo del árbol

| Nodo | Labels a entrenar | Descripción |
|---|---|---|
| IDLE (fase 0) | `idle`, `ki_charge_start` | Manos colgando vs inicio de movimiento |
| CARGA (fase 1) | `hands_together`, `single_hand_raised` | Postura de carga |
| EMPUJE (fase 2A) | `push_forward`, `push_shoulder` | Dirección del empuje doble |
| SIMPLE (fase 2B) | `push_fast`, `raise_up`, `charge_forward` | Tipo de ataque de una mano |

### Parámetros de timing recomendados

| Fase | minHoldMs | maxWaitMs | threshold |
|---|---|---|---|
| Idle → carga | 100ms | ∞ | 0.65 |
| Carga (F1) | 400ms | 5000ms | 0.75 |
| Empuje/Simple (F2) | 150–200ms | 2000–2500ms | 0.68–0.72 |

> **Ver implementación completa** en `references/gesture-phase-tree.md`:
> incluye el código completo de `PhaseTreeManager`, `extractKiFeatures`,
> `buildDragonBallTree`, debug UI, y consideraciones de diseño del árbol.

---

## 11. Debugging y visualización en escena

```typescript
// Visualizar el vector de features como esferas en la escena (debug)
export function debugFeatureVector(features: Float32Array, scene: BABYLON.Scene) {
  for (let i = 0; i < features.length; i += 3) {
    const sphere = BABYLON.MeshBuilder.CreateSphere(`dbg_${i}`, { diameter: 0.01 }, scene);
    sphere.position = new BABYLON.Vector3(features[i], features[i+1], features[i+2]);
  }
}

// Mostrar label y confianza con GUI
import { AdvancedDynamicTexture, TextBlock } from '@babylonjs/gui';
const ui = AdvancedDynamicTexture.CreateFullscreenUI('UI');
const label = new TextBlock();
label.text = 'Gesture: none';
label.color = 'white';
label.fontSize = 24;
ui.addControl(label);

// Actualizar en el loop:
scene.registerAfterRender(async () => {
  const gesture = await classifyGesture(handTracking.left.hand);
  label.text = `Gesture: ${gesture} (${(lastConfidence * 100).toFixed(0)}%)`;
});
```

---

## 12. Referencia de archivos adicionales

- `references/hand-joints-index.md` — Tabla completa de los 25 joints WebXR con sus índices y nombres
- `references/knn-api.md` — API completa de `@tensorflow-models/knn-classifier`
- `references/perf-tips.md` — Optimización de rendimiento para Quest y móviles WebXR
- `references/gesture-phase-tree.md` — **Árbol de fases para Ki attacks**: implementación completa
  de `PhaseTreeManager`, `extractKiFeatures`, `buildDragonBallTree`, debug UI, y guía de tuning

Lee estos archivos con el tool `view` cuando necesites detalles adicionales sobre joints específicos,
la API del clasificador, técnicas de optimización, o la implementación del árbol de fases.

---

## Checklist de implementación

- [ ] HTTPS habilitado en el servidor de desarrollo
- [ ] Backend TFJS seleccionado (`webgl` o `wasm`) y `tf.ready()` esperado
- [ ] Hand tracking habilitado con `WebXRFeatureName.HAND_TRACKING`
- [ ] Feature extractor devuelve vector de tamaño fijo (sin NaN/undefined)
- [ ] Mínimo 15 ejemplos por clase antes de clasificar
- [ ] `tensor.dispose()` llamado después de cada `addExample` y `predictClass`
- [ ] Flag `isClassifying` para evitar llamadas simultáneas en el render loop
- [ ] Umbral de confianza configurado por tipo de gesto (0.60–0.80)
- [ ] `saveClassifier()` conectado a un botón o trigger de guardado

### Checklist adicional para Gesture Phase Tree (Ki attacks)

- [ ] Un `KNNClassifier` instanciado **por nodo** del árbol (no uno global)
- [ ] Labels entrenados en cada nodo coinciden exactamente con las keys de `children`
- [ ] `minHoldMs` calibrado para dar tiempo de carga sin ser frustrante
- [ ] `maxWaitMs` configurado para resetear el árbol si el jugador aborta
- [ ] `PhaseTreeManager.reset()` llamado en situaciones de interrupción (daño recibido, pausa)
- [ ] Debug UI activo durante desarrollo para ver la fase actual y el path recorrido
- [ ] `extractKiFeatures` usando posición de muñecas (no dedos) para Ki attacks
- [ ] Callbacks `onEnter` conectados a efectos visuales/sonoros de carga de ki