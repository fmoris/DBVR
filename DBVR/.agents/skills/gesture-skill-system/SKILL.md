---
name: gesture-skill-system
description: >
  Crea, configura y entrega sistemas completos de reconocimiento de gestos para juegos
  Babylon.js + WebXR, basados en el GestureSkillSystem con KNN + árbol de fases.
  Usa este skill SIEMPRE que el usuario quiera:
  - Definir un nuevo ataque o gesto para un personaje de su juego VR/XR
  - Generar el código completo de un GestureSkillSystem con sus personajes y ataques
  - Agregar un personaje nuevo (Vegeta, Gohan, etc.) al sistema de gestos existente
  - Configurar fases, tiempos de carga, velocidades o umbrales de un gesto específico
  - Diseñar el árbol de fases de un ataque que comparte gestos iniciales con otros
  - Generar una sesión de entrenamiento guiada para capturar gestos en el headset
  - Exportar o cargar un modelo KNN de gestos (JSON) para un personaje
  - Depurar o afinar un gesto que no se detecta bien (umbral, velocidad, extractor)
  Trigger inmediato si el usuario menciona: "agregar ataque", "nuevo personaje",
  "gesto no funciona", "entrenar gesto", "GestureSkillSystem", "árbol de gestos",
  "ki blast", "kamehameha", "galick", "gesto VR dragon ball", o cualquier combinación
  de "gesto/ataque/poder + personaje + VR/XR/babylon/webxr".
---

# GestureSkillSystem — Skill especialista en gestos VR

Este skill genera y configura el **GestureSkillSystem**: un módulo autónomo para
Babylon.js + WebXR que reconoce gestos de Ki usando KNN + árbol de fases por personaje.

Cuando el usuario pida un gesto o personaje, este skill **entrega código listo para
copiar-pegar**, no explicaciones genéricas.

---

## Flujo de trabajo del skill

```
1. Identificar qué necesita el usuario
   ├─ ¿Personaje nuevo?         → generar bloque de config + casos FSM
   ├─ ¿Ataque nuevo?            → generar nodos del árbol + labels de entrenamiento
   ├─ ¿Sistema completo?        → generar GestureSkillSystem.js completo
   ├─ ¿Problema de detección?   → diagnosticar y proponer ajuste de parámetros
   └─ ¿Sesión de entrenamiento? → generar guía paso a paso con los labels exactos

2. Leer los archivos de referencia y la DATA del proyecto ANTES de generar código
   - references/base-system.md     → código base del GestureSkillSystem
   - references/phase-tree.md      → lógica del árbol de fases y extractores
   - references/data-mapping.md    → REGLAS para transformar JSON en labels y tiempos (NUEVO)
   - client/src/models/powers.json → metadata de ataques (nombres, gestos, tiempos)
   - client/src/models/[pj].json   → lista de ataques permitidos del personaje
   - references/training-guide.md  → protocolo de entrenamiento

3. Aplicar las reglas de mapeo de datos
   - Generar labels usando: `[pj_id]_[gesture_id_from_powers]`
   - Calcular `timing` basándose en el `charge_time` de `powers.json`.
   - Seleccionar extractores según el tipo de gesto en `powers.json`.

4. Entregar código completo, comentado y listo para usar
```

---

## Arquitectura del GestureSkillSystem

```
GestureSkillSystem
├── KNNClassifier (TF.js)          ← uno por personaje activo
├── XRHandsContext                 ← datos de manos por frame
├── FeatureExtractors              ← wristOnly / wrist+fingers / fullHand
├── GesturePhaseTree               ← árbol de decisión por personaje
│   ├── Nodo Idle
│   ├── Nodo Carga
│   └── Nodos de ataque (hojas)
├── FSM (Finite State Machine)     ← maneja estados: idle→carga→disparo→cooldown
├── ChargeSystem                   ← detecta Ki Blast rápido vs cargado
└── TrainingMode                   ← captura ejemplos directamente en headset
```

### Decisiones de diseño clave

**Un KNN por personaje, no uno global.**
Cada personaje tiene su propio modelo KNN. Esto permite cambiar de personaje
en tiempo de ejecución sin reentrenar, y guarda/carga modelos independientemente.

**Árbol de fases, no clasificación directa.**
Los ataques que comparten gestos iniciales (Kamehameha y Galick Gun ambos empiezan
con manos juntas) se resuelven progresivamente nodo a nodo, no intentando clasificar
el ataque completo de una sola vez.

**Extractor por nodo, no global.**
Cada nodo del árbol declara qué datos necesita. La mayoría usa solo muñecas
(`wristOnly`). Solo los nodos que distinguen forma de mano activan los dedos.

**Ki Blast rápido vs cargado con la misma pose.**
La velocidad de la muñeca al ejecutar, combinada con el tiempo en la pose,
determina si es un blast rápido (< 150ms + alta velocidad) o uno cargado.

---

## Plantilla de un personaje completo

Cuando el usuario pida un personaje, generar esta estructura:

```javascript
// ─────────────────────────────────────────
// PERSONAJE: [NOMBRE]
// ─────────────────────────────────────────
const [nombre]Config = {
  id: '[nombre_minusculas]',
  modelFile: 'gestures-[nombre].json',
  gestures: {
    // Pose neutra del personaje
    stance: '[nombre]_stance',

    // Ataque 1
    [ataque1]: {
      phase1:  '[nombre]_[ataque1]_phase1',   // gesto inicial
      charge:  '[nombre]_[ataque1]_charge',   // sosteniendo la carga
      release: '[nombre]_[ataque1]_release',  // disparo
    },

    // Ki Blast (común a todos los personajes, varía en forma)
    kiBlast: {
      ready:   '[nombre]_kiblast_ready',
      forward: '[nombre]_kiblast_forward',
    },
  },

  // Árbol de fases: define qué sigue a qué
  phaseTree: {
    // 'label_detectado' → 'siguiente_estado_FSM'
    '[nombre]_stance':           'base',
    '[nombre]_kiblast_ready':    'ki_blast_ready',
    '[nombre]_[ataque1]_phase1': '[ataque1]_phase1',
  },

  // Tiempos (ms) y umbrales por ataque
  timing: {
    kiBlast: { quickThresholdMs: 150, chargeStartMs: 800, maxChargeMs: 4000, quickVelocity: 0.8 },
    [ataque1]: { minChargeMs: 1200, maxChargeMs: 6000, releaseVelocity: 1.0 },
  },
};
```

---

## Reglas para diseñar un gesto

Antes de generar el árbol de un ataque, aplicar estas reglas:

### 1. Identificar fases del gesto
Todo ataque tiene al menos 3 fases: **preparación → carga → disparo**.
Algunos tienen 4 si el gesto inicial es ambiguo con otro ataque.

### 2. Elegir extractor por fase

| Tipo de fase | Extractor | Cuándo |
|---|---|---|
| Pose de posición amplia | `wristOnly` | Manos juntas, separadas, arriba, abajo |
| Forma de la mano importa | `wristAndFingertips` | Palma abierta vs puño vs apuntar |
| Gesto muy específico | `fullHand` | Transformaciones, poses únicas |

### 3. Definir timing

| Parámetro | Descripción | Rango típico |
|---|---|---|
| `minHoldMs` | Tiempo mínimo sosteniendo para confirmar la fase | 100–500ms |
| `maxWaitMs` | Timeout antes de resetear al idle | 2000–8000ms |
| `confidenceThreshold` | Umbral KNN para avanzar | 0.65–0.80 |
| `quickVelocity` | Velocidad mínima para blast rápido | 0.6–1.2 m/s |

### 4. Detectar colisiones entre ataques
Si dos ataques del mismo personaje empiezan con el mismo gesto, agregar un nodo
intermedio que los separe. Ver `references/phase-tree.md` para el patrón completo.

---

## Génesis de código: qué generar en cada pedido

### Si piden "agregar ataque [X] al personaje [Y]"
1. Generar el bloque de config del ataque dentro del personaje
2. Generar los nodos del árbol (labels + extractor + timing)
3. Generar el bloque `case` para la FSM
4. Generar la guía de entrenamiento (qué poses capturar y cuántos frames)

### Si piden "crear personaje [X] desde cero"
1. Generar el objeto de config completo del personaje
2. Generar todos los nodos del árbol de sus ataques
3. Generar todos los `case` de la FSM
4. Generar la sesión de entrenamiento completa ordenada

### Si piden "el sistema completo"
→ Leer `references/base-system.md` y entregar el `GestureSkillSystem.js` completo
  con los personajes que el usuario haya mencionado.

### Si reportan "el gesto [X] no funciona bien"
→ Leer `references/troubleshooting.md` y diagnosticar antes de proponer cambios.

---

## Archivos de referencia — leer con `view` antes de generar código

| Archivo | Cuándo leerlo |
|---|---|
| `references/base-system.md` | Siempre que se genere código del sistema base |
| `references/phase-tree.md` | Al diseñar árbol de fases de cualquier personaje |
| `references/data-mapping.md` | Obligatorio para mapear labels y tiempos desde JSON |
| `references/characters/goku.md` | Al trabajar con Goku o como template de personaje |
| `references/training-guide.md` | Al generar sesiones de entrenamiento |
| `references/troubleshooting.md` | Al diagnosticar gestos que no funcionan |

---

## Regla de oro al entregar código

> Siempre entregar código **completo, con comentarios, listo para copiar-pegar**.
> Nunca entregar fragmentos sin contexto ni pseudocódigo.
> Si el código depende de algo externo, indicarlo explícitamente con `// REQUIERE: ...`
