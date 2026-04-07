# WebXR Hand Joints — Índice completo

Referencia: https://immersive-web.github.io/webxr-hand-input/#skeleton-joints-section

En Babylon.js usa `WebXRHandJoint.<nombre>` o el índice numérico.

| Índice | Nombre W3C                       | Babylon.js Enum                              | Descripción               |
|--------|----------------------------------|----------------------------------------------|---------------------------|
| 0      | wrist                            | WebXRHandJoint.WRIST                         | Muñeca                    |
| 1      | thumb-metacarpal                 | WebXRHandJoint.THUMB_METACARPAL              | Base del pulgar           |
| 2      | thumb-phalanx-proximal           | WebXRHandJoint.THUMB_PHALANX_PROXIMAL        | Falange proximal pulgar   |
| 3      | thumb-phalanx-distal             | WebXRHandJoint.THUMB_PHALANX_DISTAL          | Falange distal pulgar     |
| 4      | thumb-tip                        | WebXRHandJoint.THUMB_TIP                     | Punta del pulgar          |
| 5      | index-finger-metacarpal          | WebXRHandJoint.INDEX_FINGER_METACARPAL       | Base del índice           |
| 6      | index-finger-phalanx-proximal    | WebXRHandJoint.INDEX_FINGER_PHALANX_PROXIMAL | Falange proximal índice   |
| 7      | index-finger-phalanx-intermediate| WebXRHandJoint.INDEX_FINGER_PHALANX_INTERMEDIATE | Falange media índice  |
| 8      | index-finger-phalanx-distal      | WebXRHandJoint.INDEX_FINGER_PHALANX_DISTAL   | Falange distal índice     |
| 9      | index-finger-tip                 | WebXRHandJoint.INDEX_FINGER_TIP              | Punta del índice          |
| 10     | middle-finger-metacarpal         | WebXRHandJoint.MIDDLE_FINGER_METACARPAL      | Base del medio            |
| 11     | middle-finger-phalanx-proximal   | WebXRHandJoint.MIDDLE_FINGER_PHALANX_PROXIMAL| Falange proximal medio    |
| 12     | middle-finger-phalanx-intermediate|WebXRHandJoint.MIDDLE_FINGER_PHALANX_INTERMEDIATE| Falange media medio  |
| 13     | middle-finger-phalanx-distal     | WebXRHandJoint.MIDDLE_FINGER_PHALANX_DISTAL  | Falange distal medio      |
| 14     | middle-finger-tip                | WebXRHandJoint.MIDDLE_FINGER_TIP             | Punta del medio           |
| 15     | ring-finger-metacarpal           | WebXRHandJoint.RING_FINGER_METACARPAL        | Base del anular           |
| 16     | ring-finger-phalanx-proximal     | WebXRHandJoint.RING_FINGER_PHALANX_PROXIMAL  | Falange proximal anular   |
| 17     | ring-finger-phalanx-intermediate | WebXRHandJoint.RING_FINGER_PHALANX_INTERMEDIATE| Falange media anular   |
| 18     | ring-finger-phalanx-distal       | WebXRHandJoint.RING_FINGER_PHALANX_DISTAL    | Falange distal anular     |
| 19     | ring-finger-tip                  | WebXRHandJoint.RING_FINGER_TIP               | Punta del anular          |
| 20     | pinky-finger-metacarpal          | WebXRHandJoint.PINKY_FINGER_METACARPAL       | Base del meñique          |
| 21     | pinky-finger-phalanx-proximal    | WebXRHandJoint.PINKY_FINGER_PHALANX_PROXIMAL | Falange proximal meñique  |
| 22     | pinky-finger-phalanx-intermediate| WebXRHandJoint.PINKY_FINGER_PHALANX_INTERMEDIATE| Falange media meñique |
| 23     | pinky-finger-phalanx-distal      | WebXRHandJoint.PINKY_FINGER_PHALANX_DISTAL   | Falange distal meñique    |
| 24     | pinky-finger-tip                 | WebXRHandJoint.PINKY_FINGER_TIP              | Punta del meñique         |

## Joints mínimos para gestos comunes

| Gesto        | Joints necesarios                              |
|--------------|------------------------------------------------|
| Puño (fist)  | 4, 9, 14, 19, 24 (tips) vs 0 (wrist)          |
| Pinza        | 4 (thumb_tip) + 9 (index_tip)                  |
| Apuntar      | 9 (index_tip) + 0 (wrist) + orientación        |
| Palma abierta| 4, 9, 14, 19, 24 (todos los tips alejados)     |
| Pulgar arriba| 4 (thumb_tip) + eje Y global del wrist         |

## Acceso en Babylon.js

```typescript
const hand = handTracking.left.hand; // o .right.hand
const tipMesh = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP);
const tipPos = tipMesh?.absolutePosition; // BABYLON.Vector3
const tipRot = tipMesh?.absoluteRotationQuaternion; // BABYLON.Quaternion
```
