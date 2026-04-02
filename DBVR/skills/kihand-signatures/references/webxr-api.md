# WebXR Hand Input API — Referencia técnica para KiHand Signatures

## Qué es la WebXR Hand Input API

La **WebXR Hand Input API** extiende la [WebXR Device API](https://www.w3.org/TR/webxr/)
para entregar datos de articulaciones de la mano como **matrices de transformación 4x4 en
tiempo real** (posición + rotación de cada hueso/articulación).

Estos datos permiten:
- Representar "manos virtuales" 3D en el navegador sin plugins
- Detectar gestos por distancia, ángulo u orientación entre articulaciones
- Mapear movimientos de manos a acciones de juego (disparo, selección, rotación de objetos)

> **Fuente académica**: *A Novel Framework for Hand Visualization in Web-Based Collaborative XR*
> (IEEE) describe cómo usar estos datos en entornos XR colaborativos para manipular objetos
> en juegos multijugador — el mismo principio que usamos para los ataques Ki.

---

## Las 26 articulaciones del estándar WebXR

El estándar define exactamente **25 joints + muñeca** por mano:

```
Muñeca:
  wrist

Pulgar (4 joints):
  thumb-metacarpal → thumb-phalanx-proximal → thumb-phalanx-distal → thumb-tip

Índice (4 joints):
  index-finger-metacarpal → index-finger-phalanx-proximal
  → index-finger-phalanx-intermediate → index-finger-phalanx-distal → index-finger-tip

Medio, Anular, Meñique: misma estructura × 3
```

En Babylon.js se accede via `WebXRHandJoint` enum:

```typescript
import {
  WebXRHandJoint,
} from '@babylonjs/core/XR/features/WebXRHandTracking.js';

// Joints más usados en Ki gestures:
WebXRHandJoint.WRIST
WebXRHandJoint.THUMB_TIP
WebXRHandJoint.INDEX_FINGER_TIP
WebXRHandJoint.INDEX_FINGER_PHALANX_PROXIMAL
WebXRHandJoint.MIDDLE_FINGER_TIP
WebXRHandJoint.MIDDLE_FINGER_PHALANX_PROXIMAL
WebXRHandJoint.RING_FINGER_TIP
WebXRHandJoint.PINKY_TIP
```

---

## Cómo habilitar Hand Tracking en Babylon.js

### Paso 1 — Habilitar el módulo

```typescript
import { WebXRHandTracking } from '@babylonjs/core/XR/features/WebXRHandTracking.js';
import { WebXRFeatureName } from '@babylonjs/core/XR/webXRFeaturesManager.js';

// Después de crear WebXRDefaultExperience:
const handFeature = xrHelper.featuresManager.enableFeature(
  WebXRFeatureName.HAND_TRACKING,
  'stable',
  { xrInput: xrHelper.input },
) as WebXRHandTracking;
```

### Paso 2 — Suscribirse a eventos de mano

```typescript
handFeature.onHandAddedObservable.add((hand: WebXRHand) => {
  console.log('Mano detectada:', hand.xrController.handedness); // 'left' | 'right'
  // Aquí adjuntas detectores de gestos
});

handFeature.onHandRemovedObservable.add((hand: WebXRHand) => {
  // Limpiar estado cuando el tracking se pierde
});
```

### Paso 3 — Leer articulaciones en cada frame

```typescript
scene.onBeforeRenderObservable.add(() => {
  // Obtener la malla (TransformNode) de una articulación
  const wristMesh  = hand.getJointMesh(WebXRHandJoint.WRIST);
  const indexMesh  = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP);

  if (!wristMesh || !indexMesh) return; // tracking no disponible ese frame

  // Posición en espacio mundo
  const wristPos = wristMesh.absolutePosition;   // Vector3
  const indexPos = indexMesh.absolutePosition;   // Vector3

  // Dirección de muñeca → yema del índice
  const fingerDir = indexPos.subtract(wristPos).normalize();

  // Distancia entre dos articulaciones (útil para detectar dedos juntos)
  const dist = Vector3.Distance(wristPos, indexPos);
});
```

---

## Patrones de la API y su uso en Ki gestures

La API nativa soporta pellizco (`pinch`) y agarre (`grab`), pero **los gestos Ki son místicos**
y no interactúan con objetos de la escena. Esta tabla muestra cómo se reasignan:

| Patrón API estándar | Uso típico | Uso en KiHand Signatures |
|---|---|---|
| Distancia pulgar-índice < 3cm | Pellizco / selección | ❌ No usado |
| Distancia anular-palma < 7cm | Dedo recogido | ✅ Ki-Blast: detectar anular recogido |
| `palmNormal` hacia adelante (-Z) | Apuntar con palma | ✅ Kamehameha: palma al frente |
| `palmNormal` hacia arriba (+Y) | Palma abierta arriba | ✅ Genkidama: manos elevadas |
| Posición lateral de muñeca | Movimiento | ✅ Galick: manos laterales |
| Índice extendido hacia adelante | Puntero láser | ✅ Ki-Blast: cañón de energía |

> **Referencia**: *Sensor Fusion Approach for Precise Hand Tracking in VR-based HCI* describe
> técnicas de fusión de sensores para mejorar estabilidad del tracking — importante al diseñar
> el buffer de frames (`confirmFrames`) para evitar falsos positivos.

---

## Consideraciones de rendimiento (Quest 2/3)

Basado en la evaluación de la *WebXR Device API Performance Evaluation*:

- El cálculo de articulaciones ocurre en la GPU del headset — no añade carga a tu JS.
- La lectura de `getJointMesh().absolutePosition` es O(1) — segura en el render loop.
- Los `onBeforeRenderObservable` son síncronos — evita operaciones costosas (red, I/O) dentro.
- En Quest 2: limita la complejidad de heurísticas a operaciones vectoriales simples (dot, distance).
- Si el tracking se pierde (`getJointMesh` devuelve `null`), el sistema debe tolerar frames nulos
  sin crashear — siempre usa guards `if (!mesh) return`.

---

## Malla de mano visual (opcional)

Babylon.js puede renderizar automáticamente las manos del usuario:

```typescript
// Mostrar mallas de mano (útil en desarrollo para depurar gestos)
handFeature.showHandMeshes = true;

// Ocultar en producción (el juego usa sus propios efectos visuales Ki)
handFeature.showHandMeshes = false;
```

La malla usa `XRHandGeometryMesh` internamente. No necesitas gestionarla — Babylon.js la
actualiza automáticamente cada frame con los datos de la API.

---

## Detección de soporte del dispositivo

No todos los dispositivos soportan hand tracking:

```typescript
async function checkHandTrackingSupport(xrHelper: WebXRDefaultExperience): Promise<boolean> {
  try {
    const feature = xrHelper.featuresManager.enableFeature(
      WebXRFeatureName.HAND_TRACKING, 'stable',
      { xrInput: xrHelper.input },
    );
    return feature !== null;
  } catch {
    return false;
  }
}

// Uso:
const supported = await checkHandTrackingSupport(xrHelper);
if (!supported) {
  showFallbackUI('Hand tracking no disponible — actívalo en Ajustes del Quest');
}
```

En Quest: **Ajustes → Movimiento de manos y controladores → Seguimiento de manos** debe
estar activado para que la API devuelva datos.

---

## Referencias técnicas completas

1. **IEEE** — *A Novel Framework for Hand Visualization in Web-Based Collaborative XR*
   Framework para visualización de manos en WebXR colaborativo; base para entender mapeo
   de articulaciones a objetos en juegos multijugador.

2. **MediaPipe Hands** — *On-device Real-time Hand Tracking*
   Pipeline de seguimiento desde cámara RGB; arquitectura de referencia para entender cómo
   se procesan los 21 landmarks de mano que la WebXR API entrega.

3. **Performance Evaluation of Ground AR Anchor with WebXR Device API**
   Evaluación de estabilidad y rendimiento de la WebXR Device API en distintos headsets;
   relevante para calibrar `confirmFrames` según el dispositivo objetivo.

4. **Babylon.js WebXR Docs — Hands / Hand Tracking**
   Documentación oficial: activación del módulo, acceso a articulaciones, ejemplos de código.
   URL: `https://doc.babylonjs.com/features/featuresDeepDive/webXR/WebXRHandTracking`

5. **Sensor Fusion Approach for Precise Hand Tracking in VR-based HCI**
   Técnicas de fusión de sensores para mejorar estabilidad — fundamento teórico del buffer
   de frames (`FrameBuffer`) usado en este skill para suavizar el ruido del tracking.

6. **Hand-based Web-based Collaborative XR with Hand Visualization**
   Marcos de interacción con manos en WebXR; inspiración para mecánicas de juego como
   carga de energía (Kamehameha) y gestos de invocación (Genkidama).
