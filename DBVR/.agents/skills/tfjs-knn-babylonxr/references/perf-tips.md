# Performance Tips — TF.js KNN + Babylon.js WebXR

## Problema central: competencia de GPU

Babylon.js y TensorFlow.js con backend `webgl` **comparten el contexto WebGL**.
Las inferencias frecuentes en el render loop pueden causar frame drops.

## Estrategias de optimización

### 1. Throttle de clasificación (más efectivo para KNN)

KNN es muy liviano, pero no lo llames en CADA frame (60fps). Clasifica cada 5–10 frames:

```typescript
let frameCount = 0;
const CLASSIFY_EVERY_N_FRAMES = 6; // ~10 veces por segundo a 60fps

scene.registerAfterRender(async () => {
  frameCount++;
  if (frameCount % CLASSIFY_EVERY_N_FRAMES !== 0) return;
  // ... clasificar aquí
});
```

### 2. Flag de mutex para evitar clasificaciones simultáneas

```typescript
let classifyBusy = false;
scene.registerAfterRender(async () => {
  if (classifyBusy) return;
  classifyBusy = true;
  try {
    await classifyGesture(hand);
  } finally {
    classifyBusy = false;
  }
});
```

### 3. Backend WASM para dispositivos de baja potencia (Quest 1, móviles)

```typescript
import '@tensorflow/tfjs-backend-wasm';
await tf.setBackend('wasm');
```
WASM no compite con el GPU de Babylon.js. Es 2–5x más lento que WebGL para modelos grandes,
pero KNN con vectores de <100 dimensiones es suficientemente rápido en WASM (<5ms).

### 4. Elegir el backend según el dispositivo

```typescript
async function selectBackend() {
  // Detectar si es Quest (user agent heurístico)
  const isQuest = /Quest/.test(navigator.userAgent);
  if (isQuest) {
    await tf.setBackend('wasm'); // más estable en Quest
  } else {
    await tf.setBackend('webgl'); // más rápido en desktop/PC VR
  }
  await tf.ready();
}
```

### 5. Reduce dimensiones del vector de features

Menos features = KNN más rápido. Para gestos de mano:
- **Mínimo útil**: 15–20 valores (5 tips relativos al wrist)
- **Estándar**: 27 valores (9 joints × 3 coords)
- **Completo**: 75 valores (25 joints × 3 coords) — raramente necesario

### 6. Precalentar el backend antes de entrar a WebXR

```typescript
// Ejecutar una inferencia dummy antes de la sesión XR
// para compilar shaders WebGL y evitar spike al primer uso
await tf.ready();
const warmup = tf.zeros([1, 27]);
// No usamos predictClass (necesita ejemplos), solo operaciones básicas
const result = tf.norm(warmup);
result.dispose();
warmup.dispose();
```

### 7. Gestión de memoria con `tf.tidy()`

```typescript
// Envolver operaciones intermedias en tidy() para auto-dispose
const features = tf.tidy(() => {
  const raw = tf.tensor1d(extractHandFeatures(hand));
  return tf.div(raw, tf.norm(raw)); // normalización L2
});
// features se debe dispose manualmente (tidy() no dispone el valor retornado)
const result = await classifier.predictClass(features, 3);
features.dispose();
```

### 8. Monitorear memoria de tensores en desarrollo

```typescript
// En consola del navegador, verifica que no haya leaks:
console.log(tf.memory());
// { numTensors: N, numDataBuffers: M, numBytes: X, unreliable: false }
// numTensors debería ser estable entre frames
```

## Benchmarks orientativos (KNN, vector 27D, k=3)

| Dispositivo           | Backend | Inferencia | FPS impacto |
|-----------------------|---------|------------|-------------|
| PC desktop (RTX 3080) | webgl   | < 1ms      | Imperceptible |
| Meta Quest 3          | webgl   | 2–5ms      | ~1-2 frames  |
| Meta Quest 2          | wasm    | 5–15ms     | ~1-2 frames  |
| Meta Quest 1          | wasm    | 15–30ms    | Usar throttle |
| iPhone 13 (Safari)    | wasm    | 8–20ms     | Usar throttle |

## Si el problema persiste: mover a WebWorker

KNN en WASM puede correr en WebWorker (no bloquea UI thread).
Pasar features como `Float32Array` vía `postMessage` con `transferable`.
Ver: https://erdem.pl/2020/02/making-tensorflow-js-work-faster-with-web-workers/
