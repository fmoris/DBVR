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
Babylon.js + WebXR que reconoce gestos de Ki usando KNN + árbol de fases.

Cuando el usuario pida un gesto o personaje, este skill **entrega código listo para
copiar-pegar**, no explicaciones genéricas.

---

## Flujo de trabajo del skill

```
1. Identificar qué necesita el usuario
   ├─ ¿Personaje nuevo?         → generar bloque de config (gestureIds) + casos FSM
   ├─ ¿Ataque nuevo?            → generar nodos del árbol + labels de entrenamiento
   ├─ ¿Sistema completo?        → generar GestureSkillSystem.js completo
   ├─ ¿Problema de detección?   → diagnosticar y proponer ajuste de parámetros
   └─ ¿Sesión de entrenamiento? → generar guía paso a paso con los labels exactos

2. Leer los archivos de referencia y la DATA del proyecto ANTES de generar código
   - references/base-system.md     → código base del GestureSkillSystem
   - references/phase-tree.md      → lógica del árbol de fases y extractores
   - references/characters/goku.md  → template de personaje modular (NUEVO)
   - server/data/gestures/         → verificar qué movimientos YA existen
   - references/training-guide.md  → protocolo de entrenamiento

3. Aplicar las reglas de mapeo de datos
   - Generar labels únicos por movimiento (ej: `kame_prep`, `kame_fire`)
   - Calcular `timing` basándose en la técnica.
   - Seleccionar extractores según el tipo de gesto.

4. Entregar código completo, comentado y listo para usar
```

---

## Arquitectura del GestureSkillSystem

```
GestureSkillSystem
├── KNNClassifier (TF.js)          ← uno por personaje activo (reconstruido en memoria)
├── XRHandsContext                 ← datos de manos por frame
├── FeatureExtractors              ← wristOnly (16) / wristAndFingertips (46)
├── GesturePhaseTree               ← FSM + árbol de decisión por personaje
│   ├── Nodo Idle
│   ├── Nodo Preparación (Ph1)
│   └── Nodo Activación (Ph2)
├── DimensionValidation            ← Rechaza mismatch de features
├── SessionHistory (3D)            ← Memoria de trabajo (combinación de modular)
└── ModularSync                    ← Sincronización por movimiento (via /api/gestures/movement/:id)
```

### Decisiones de diseño clave

**Arquitectura Movement-Centric (Modular)**
Los gestos son independientes del personaje. Cada movimiento (ej: `recharge_prep`) es un archivo `.json` independiente en el servidor. Esto permite compartir habilidades y actualizar ataques sin descargar todo el modelo de nuevo.

**SSOT en Servidor**
Se ha eliminado la dependencia de `localStorage` para la carga principal. El servidor es la única fuente de verdad. La sincronización ocurre al finalizar el entrenamiento de un label específico.

**Estandarización de 2 Fases (Regla del Árbol)**
Cualquier movimiento debe seguir el patrón de al menos 2 fases: **Preparación** (posicionamiento inicial) y **Activación/Fuego** (acción o loop). Esto garantiza transiciones estables y evita disparos accidentales desde el estado Idle.

---

## Plantilla de un personaje completo

Cuando el usuario pida un personaje, generar esta estructura:

```javascript
// ─────────────────────────────────────────
// PERSONAJE: [NOMBRE] (CharacterConfigs.ts)
// ─────────────────────────────────────────
export const [NOMBRE]_CONFIG: CharacterConfig = {
  id: '[pj_id]',
  gestureIds: [
    'recharge_prep', 
    'recharge_active', 
    '[mov]_preparation', 
    '[mov]_firing'
  ],
  extractors: {
    'idle': 'wristOnly',
    '[mov]_preparation': 'wristOnly',
    '[mov]_firing': 'wristAndFingertips'
  },
  thresholds: {
    'idle': 0.70,
    '[mov]_preparation': 0.75,
    '[mov]_firing': 0.85
  },
  fsmHandler: function(this: GestureSkillSystem, gesture, confidence, ctx, now) {
      // Usar constantes locales para mapear labels a lógica
      const g = {
          prep: '[mov]_preparation',
          fire: '[mov]_firing'
      };
      
      switch(this.currentState) {
          case 'idle':
              if (gesture === g.prep) {
                  this.setState('[mov]_charge');
                  this.startCharge('[mov]', 'both', now);
              }
              break;
          // ... resto de estados
      }
  }
};
```

---

## Reglas para diseñar un gesto

### 1. Identificar fases del gesto
Mínimo 2 fases obligatorias por movimiento para consistencia con el sistema de árbol.

### 2. Elegir extractor por fase

| Tipo de fase | Extractor | Cuándo |
|---|---|---|
| Pose amplia | `wristOnly` | Preparación, manos separadas |
| Forma de mano | `wristAndFingertips` | Fuego, garras, puños, señales |

### 3. Sincronización Modular
**REGLA CRÍTICA:** Al guardar (`saveModel`), el GSS solo sincroniza el `trainingLabel` activo. Nunca sobrescribir archivos modulares que no se han tocado en la sesión actual.

---

## Regla de oro al entregar código

> Siempre entregar código **completo, con comentarios, listo para copiar-pegar**.
