# @tensorflow-models/knn-classifier — API completa

Fuente: https://github.com/tensorflow/tfjs-models/tree/master/knn-classifier

## Instalación

```bash
npm install @tensorflow/tfjs @tensorflow-models/knn-classifier
```

CDN:
```html
<script src="https://cdn.jsdelivr.net/npm/@tensorflow/tfjs"></script>
<script src="https://cdn.jsdelivr.net/npm/@tensorflow-models/knn-classifier"></script>
```

## Crear el clasificador

```typescript
import * as knnClassifier from '@tensorflow-models/knn-classifier';
const classifier = knnClassifier.create();
```

## Métodos

### `classifier.addExample(example, label)`
Añade un tensor de features asociado a una clase/etiqueta.

```typescript
classifier.addExample(
  example: tf.Tensor,   // tensor 1D o 2D de features
  label: number | string // etiqueta de la clase
): void
```

### `classifier.predictClass(input, k?)`
Clasifica un input y devuelve la clase predicha.

```typescript
const result = await classifier.predictClass(
  input: tf.Tensor,  // mismo shape que los ejemplos de entrenamiento
  k: number = 3      // número de vecinos (default: 3)
);
// result = {
//   label: string,
//   classIndex: number,
//   confidences: { [label: string]: number }  // suma = 1.0
// }
```

### `classifier.getClassExampleCount()`
Retorna el número de ejemplos por clase.
```typescript
const counts = classifier.getClassExampleCount();
// { 'fist': 20, 'open': 18, 'point': 22 }
```

### `classifier.getNumClasses()`
Número total de clases registradas.
```typescript
const n = classifier.getNumClasses(); // 3
```

### `classifier.getClassifierDataset()`
Retorna el dataset interno como `{ [label]: Tensor2D }`. Útil para persistencia.

### `classifier.setClassifierDataset(dataset)`
Restaura un dataset previamente guardado.
```typescript
classifier.setClassifierDataset({
  'fist': tf.tensor2d([[...], [...]])
});
```

### `classifier.clearClass(label)`
Elimina todos los ejemplos de una clase específica.

### `classifier.dispose()`
Libera toda la memoria WebGL del clasificador.

## Parámetros de k

| k  | Comportamiento                                      |
|----|-----------------------------------------------------|
| 1  | Más rápido, más sensible al ruido                   |
| 3  | Equilibrio recomendado (default)                    |
| 5  | Más robusto, necesita más ejemplos por clase        |
| 7+ | Solo útil con 50+ ejemplos por clase                |

**Regla**: Si `ejemplos_por_clase < k`, el sistema usa `k = ejemplos_por_clase`.

## Umbral de confianza recomendado

```typescript
const result = await classifier.predictClass(tensor, 3);
const confidence = result.confidences[result.label];

if (confidence > 0.70) {
  // acción con alta certeza
} else if (confidence > 0.50) {
  // acción con certeza media (considera feedback visual al jugador)
} else {
  // ignorar — gesto ambiguo
}
```

## Flujo completo mínimo

```typescript
import * as tf from '@tensorflow/tfjs';
import * as knnClassifier from '@tensorflow-models/knn-classifier';

await tf.setBackend('webgl');
await tf.ready();

const classifier = knnClassifier.create();

// Entrenar
const features1 = new Float32Array([0.1, 0.9, 0.2, 0.8]);
const t1 = tf.tensor1d(features1);
classifier.addExample(t1, 'gesture_a');
t1.dispose();

// Clasificar
const input = tf.tensor1d(new Float32Array([0.15, 0.85, 0.25, 0.75]));
const result = await classifier.predictClass(input, 3);
input.dispose();

console.log(result.label); // 'gesture_a'
console.log(result.confidences); // { gesture_a: 1.0 }
```
