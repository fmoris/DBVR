---
name: kihand-signatures
description: >
  Skill especializado para implementar reconocimiento de gestos de manos Dragon Ball
  en el framework Antigravity (Babylon.js + WebXR). Usa este skill SIEMPRE que el usuario quiera:
  - Crear o implementar ataques de Ki con manos en WebXR / Meta Quest
  - Reconocer gestos tipo Kamehameha, Ki-Blast, Galick o Genkidama con hand tracking
  - Integrar el sistema KiHand Signatures en un juego Antigravity existente
  - Configurar poderes de energía sin pellizco ni agarre de objetos (gestos místicos)
  - Conectar eventos OnKiGestureDetected con animaciones y efectos visuales de energía
  - Ajustar sensibilidad, niveles o heurísticas de detección de gestos de Ki
  Trigger inmediato si el usuario menciona: "Kamehameha", "Ki-Blast", "Galick", "Genkidama",
  "gestos de manos Dragon Ball", "ataques de energía WebXR", "hand tracking ki", "KiHand",
  o cualquier combinación de "poderes" + "manos" + "VR/XR/Quest".
---

# KiHand Signatures — Skill para Antigravity

Sistema de reconocimiento de gestos de manos inspirados en Dragon Ball para el framework
**Antigravity** (Babylon.js + WebXR). Todos los gestos son de tipo "místico/energético":
sin pellizco ni interacción física con el entorno.

---

## Fundamentos: WebXR Hand Tracking API

### Qué es

La **WebXR Hand Input API** extiende la WebXR Device API para entregar datos de articulaciones
de la mano (huesos y articulaciones) como **matrices de transformación en tiempo real**.
Estos datos permiten representar "manos virtuales" 3D en el navegador y detectar gestos,
distancias entre dedos, orientación de la palma, y mapearlos a acciones de juego.

### Cómo funciona en Babylon.js

Babylon.js encapsula la API en el módulo `WebXRHandTracking`. Al habilitarlo:

- Expone la malla 3D de cada mano (`XRHandGeometryMesh`) y los datos de cada articulación (`XRHand`).
- Permite adjuntar objetos 3D a cada articulación (dedos, muñeca, palma).
- Proporciona coordenadas en tiempo real de las 26 articulaciones para calcular distancias,
  ángulos y orientaciones.

**Patrones comunes de la API** (que este skill usa de forma mística/energética):

| Patrón API | Uso en Ki Attacks |
|---|---|
| Distancia pulgar–índice (pellizco) | NO usado — gestos son místicos, no de agarre |
| Orientación de palma | SÍ — detectar si la palma apunta al frente (Kamehameha) |
| Posición de articulaciones | SÍ — detectar manos elevadas (Genkidama), laterales (Galick) |
| Puntero láser desde dedo | SÍ — índice+medio como cañón (Ki-Blast) |

> **Nota de diseño**: los gestos Ki evitan pellizco y agarre físico deliberadamente.
> Se basan en orientación y posición, no en interacción con objetos de la escena.

### Referencias académicas y técnicas

- **IEEE** — *A Novel Framework for Hand Visualization in Web-Based Collaborative XR*:
  framework para visualización e interacción de manos en WebXR colaborativo; útil para
  entender cómo mapear movimientos de manos a objetos en juegos multijugador.
- **MediaPipe Hands** — *On-device Real-time Hand Tracking*: pipeline de seguimiento desde
  cámara RGB, base de muchos sistemas de hand tracking en web-based XR.
- **WebXR Device API Performance Evaluation**: evaluación de estabilidad y rendimiento en
  distintos headsets; relevante para asegurar que el juego corra fluido en Quest 2/3.
- **Babylon.js WebXR Docs** (sección Hands / Hand Tracking): documentación oficial para
  activar el módulo y acceder a las articulaciones.
- **Sensor Fusion for Precise Hand Tracking in VR-based HCI**: marcos para interacción con
  manos en entornos WebXR (puzzles, manipulación de objetos); inspiración para mecánicas Ki.

---

## Archivos de referencia

- `references/webxr-api.md` — Fundamentos de la WebXR Hand Input API, joints, matrices y patrones
- `references/gesture-detection.md` — Heurísticas, articulaciones y algoritmos de detección
- `references/ki-ability-component.md` — Patrón Component-System y KiAbilityComponent
- `references/vfx-integration.md` — Efectos visuales sobre la mano y proyectiles de energía
- `references/level-config.md` — Guía para diseñadores de niveles

Lee el archivo de referencia relevante según la subtarea del usuario:
- Dudas sobre la API nativa o Babylon.js → `webxr-api.md`
- Heurísticas y detección de poses → `gesture-detection.md`
- Conectar gestos con poderes del juego → `ki-ability-component.md`
- Partículas, beams, proyectiles → `vfx-integration.md`
- Configuración sin código para diseñadores → `level-config.md`

---

## Arquitectura del Sistema

```
KiHandSignaturesSystem (ComponentSystem)
│
├── HandGestureDetector         ← detecta poses por articulaciones
│   ├── KamehamehaDetector
│   ├── KiBlastDetector
│   ├── GalickDetector
│   └── GenkidamaDetector
│
├── GestureEventBus             ← emite OnKiGestureDetected
│
└── KiAbilityComponent          ← escucha eventos y dispara poderes
    ├── KamehamehaAbility       (sostenido, se carga)
    ├── KiBlastAbility          (disparo rápido)
    ├── GalickAbility           (bomba con invocación)
    └── GenkidamaAbility        (gran ataque, cooldown alto)
```

---

## Código esqueleto principal

### 1. Tipos y eventos

```typescript
// src/ki/types.ts

export type KiGestureName =
  | 'Kamehameha'
  | 'KiBlast'
  | 'Galick'
  | 'Genkidama';

export interface KiGestureEvent {
  gesture: KiGestureName;
  hand: 'left' | 'right' | 'both';
  chargeLevel: number;          // 0.0 – 1.0
  origin: import('@babylonjs/core/Maths/math.vector').Vector3;
  direction: import('@babylonjs/core/Maths/math.vector').Vector3;
}

export interface KiSkillConfig {
  /** Umbral de cos(ángulo) para considerar dedos alineados (default 0.85) */
  alignmentThreshold: number;
  /** Frames consecutivos necesarios para confirmar gesto (default 12) */
  confirmFrames: number;
  /** Segundos de carga para Kamehameha nivel máximo (default 2.5) */
  kamehamehaMaxCharge: number;
  /** Cooldown en segundos para Genkidama (default 30) */
  genkidamaCooldown: number;
  /** Nivel 1-5 que escala sensibilidad y efectos */
  level: number;
}

export const DEFAULT_KI_CONFIG: KiSkillConfig = {
  alignmentThreshold: 0.85,
  confirmFrames: 12,
  kamehamehaMaxCharge: 2.5,
  genkidamaCooldown: 30,
  level: 1,
};
```

---

### 2. Sistema principal

```typescript
// src/ki/KiHandSignaturesSystem.ts
import { Scene } from '@babylonjs/core/scene.js';
import { Observable } from '@babylonjs/core/Misc/observable.js';
import { WebXRHandTracking, WebXRHand } from '@babylonjs/core/XR/features/WebXRHandTracking.js';
import { WebXRFeatureName } from '@babylonjs/core/XR/webXRFeaturesManager.js';
import { WebXRDefaultExperience } from '@babylonjs/core/XR/webXRDefaultExperience.js';
import { KiGestureEvent, KiSkillConfig, DEFAULT_KI_CONFIG } from './types';
import { HandGestureDetector } from './HandGestureDetector';

export class KiHandSignaturesSystem {
  /** Evento principal: suscríbete aquí para recibir gestos detectados */
  public readonly onKiGestureDetected = new Observable<KiGestureEvent>();

  private detector!: HandGestureDetector;
  private handFeature!: WebXRHandTracking;
  private supported = false;

  constructor(
    private scene: Scene,
    private config: KiSkillConfig = DEFAULT_KI_CONFIG,
  ) {}

  /** Llama esto después de crear WebXRDefaultExperience */
  async initialize(xrHelper: WebXRDefaultExperience): Promise<boolean> {
    const fm = xrHelper.featuresManager;

    // Verifica soporte de hand tracking
    if (!fm.getEnabledFeature(WebXRFeatureName.HAND_TRACKING)) {
      try {
        this.handFeature = fm.enableFeature(
          WebXRFeatureName.HAND_TRACKING,
          'stable',
          { xrInput: xrHelper.input },
        ) as WebXRHandTracking;
      } catch {
        console.warn('[KiHandSignatures] Hand tracking no soportado en este dispositivo.');
        return false;
      }
    } else {
      this.handFeature = fm.getEnabledFeature(
        WebXRFeatureName.HAND_TRACKING,
      ) as WebXRHandTracking;
    }

    this.detector = new HandGestureDetector(this.scene, this.config);
    this.detector.onGestureDetected.add((evt) => this.onKiGestureDetected.notifyObservers(evt));

    this.handFeature.onHandAddedObservable.add((hand: WebXRHand) => {
      this.detector.registerHand(hand);
    });
    this.handFeature.onHandRemovedObservable.add((hand: WebXRHand) => {
      this.detector.unregisterHand(hand);
    });

    this.supported = true;
    console.log('[KiHandSignatures] Sistema inicializado correctamente.');
    return true;
  }

  updateConfig(partial: Partial<KiSkillConfig>): void {
    Object.assign(this.config, partial);
    this.detector?.updateConfig(this.config);
  }

  dispose(): void {
    this.detector?.dispose();
    this.onKiGestureDetected.clear();
  }
}
```

---

### 3. Detector de gestos

```typescript
// src/ki/HandGestureDetector.ts
import { Scene } from '@babylonjs/core/scene.js';
import { Observable } from '@babylonjs/core/Misc/observable.js';
import { Vector3 } from '@babylonjs/core/Maths/math.vector.js';
import {
  WebXRHand,
  WebXRHandJoint,
} from '@babylonjs/core/XR/features/WebXRHandTracking.js';
import { KiGestureEvent, KiGestureName, KiSkillConfig } from './types';

interface HandState {
  hand: WebXRHand;
  confirmCounter: Record<KiGestureName, number>;
  chargeTimer: number;
  lastPalmDir: Vector3;
}

export class HandGestureDetector {
  public readonly onGestureDetected = new Observable<KiGestureEvent>();
  private states = new Map<string, HandState>();
  private renderObs: (() => void) | null = null;

  constructor(private scene: Scene, private config: KiSkillConfig) {
    this.renderObs = () => this.tick();
    scene.onBeforeRenderObservable.add(this.renderObs);
  }

  registerHand(hand: WebXRHand): void {
    const id = hand.xrController.uniqueId;
    this.states.set(id, {
      hand,
      confirmCounter: { Kamehameha: 0, KiBlast: 0, Galick: 0, Genkidama: 0 },
      chargeTimer: 0,
      lastPalmDir: Vector3.Zero(),
    });
  }

  unregisterHand(hand: WebXRHand): void {
    this.states.delete(hand.xrController.uniqueId);
  }

  updateConfig(config: KiSkillConfig): void {
    this.config = config;
  }

  private tick(): void {
    // Detectores de gestos individuales se evalúan en references/gesture-detection.md
    for (const state of this.states.values()) {
      this.evaluateKamehameha(state);
      this.evaluateKiBlast(state);
      this.evaluateGalick(state);
      this.evaluateGenkidama(state);
    }
  }

  /**
   * Kamehameha: palma extendida hacia adelante, dedos juntos, mantenida.
   * Requiere AMBAS manos. Ver references/gesture-detection.md para heurísticas completas.
   */
  private evaluateKamehameha(state: HandState): void {
    const { hand, confirmCounter } = state;
    const wrist  = hand.getJointMesh(WebXRHandJoint.WRIST);
    const middle = hand.getJointMesh(WebXRHandJoint.MIDDLE_FINGER_TIP);
    if (!wrist || !middle) return;

    const palmDir = middle.absolutePosition.subtract(wrist.absolutePosition).normalize();
    const forward  = new Vector3(0, 0, -1); // cámara hacia adelante en XR
    const aligned  = Vector3.Dot(palmDir, forward);

    if (aligned > this.config.alignmentThreshold) {
      confirmCounter.Kamehameha++;
      state.chargeTimer += this.scene.getEngine().getDeltaTime() / 1000;
    } else {
      if (confirmCounter.Kamehameha >= this.config.confirmFrames) {
        // El usuario soltó la pose → dispara el ataque cargado
        const charge = Math.min(state.chargeTimer / this.config.kamehamehaMaxCharge, 1.0);
        this.fire('Kamehameha', 'both', charge, wrist.absolutePosition, forward, state);
      }
      confirmCounter.Kamehameha = 0;
      state.chargeTimer = 0;
    }
  }

  /** Ki-Blast: índice y medio apuntando, mano extendida. */
  private evaluateKiBlast(state: HandState): void {
    const { hand, confirmCounter } = state;
    const indexTip  = hand.getJointMesh(WebXRHandJoint.INDEX_FINGER_TIP);
    const middleTip = hand.getJointMesh(WebXRHandJoint.MIDDLE_FINGER_TIP);
    const ringTip   = hand.getJointMesh(WebXRHandJoint.RING_FINGER_TIP);
    const wrist     = hand.getJointMesh(WebXRHandJoint.WRIST);
    if (!indexTip || !middleTip || !ringTip || !wrist) return;

    const gunDir = indexTip.absolutePosition.subtract(wrist.absolutePosition).normalize();
    const forward = new Vector3(0, 0, -1);
    // Ring finger debe estar recogido (cerca de la palma)
    const ringFolded = Vector3.Distance(
      ringTip.absolutePosition, wrist.absolutePosition,
    ) < 0.07;

    if (Vector3.Dot(gunDir, forward) > this.config.alignmentThreshold && ringFolded) {
      confirmCounter.KiBlast++;
      if (confirmCounter.KiBlast === this.config.confirmFrames) {
        this.fire('KiBlast', 'right', 1.0, wrist.absolutePosition, gunDir, state);
      }
    } else {
      confirmCounter.KiBlast = 0;
    }
  }

  /** Galick: manos unidas lateralmente + movimiento hacia adelante. */
  private evaluateGalick(state: HandState): void {
    // Ver references/gesture-detection.md § Galick para el gesto dinámico completo
    const { hand, confirmCounter } = state;
    const wrist = hand.getJointMesh(WebXRHandJoint.WRIST);
    if (!wrist) return;

    const lateral = Math.abs(wrist.absolutePosition.x) > 0.25;
    if (lateral) {
      confirmCounter.Galick++;
      if (confirmCounter.Galick === this.config.confirmFrames) {
        const dir = new Vector3(-Math.sign(wrist.absolutePosition.x), 0, -1).normalize();
        this.fire('Galick', 'both', 1.0, wrist.absolutePosition, dir, state);
      }
    } else {
      confirmCounter.Galick = 0;
    }
  }

  /** Genkidama: manos abiertas y elevadas, luego unidas hacia adelante. */
  private evaluateGenkidama(state: HandState): void {
    const { hand, confirmCounter } = state;
    const wrist = hand.getJointMesh(WebXRHandJoint.WRIST);
    if (!wrist) return;

    const raised = wrist.absolutePosition.y > 1.5; // manos por encima de la cabeza
    if (raised) {
      confirmCounter.Genkidama++;
      if (confirmCounter.Genkidama === this.config.confirmFrames * 3) {
        // Genkidama requiere mantener la pose 3x más
        this.fire('Genkidama', 'both', 1.0, wrist.absolutePosition,
          new Vector3(0, 0, -1), state);
      }
    } else {
      confirmCounter.Genkidama = 0;
    }
  }

  private fire(
    gesture: KiGestureName,
    hand: KiGestureEvent['hand'],
    chargeLevel: number,
    origin: Vector3,
    direction: Vector3,
    state: HandState,
  ): void {
    // Resetea contador tras disparar
    state.confirmCounter[gesture] = 0;
    this.onGestureDetected.notifyObservers({ gesture, hand, chargeLevel, origin, direction });
  }

  dispose(): void {
    if (this.renderObs) {
      this.scene.onBeforeRenderObservable.removeCallback(this.renderObs);
    }
    this.onGestureDetected.clear();
  }
}
```

---

### 4. KiAbilityComponent (escucha eventos y lanza el poder)

```typescript
// src/ki/KiAbilityComponent.ts
import { KiGestureEvent, KiGestureName } from './types';
import { KiHandSignaturesSystem } from './KiHandSignaturesSystem';

type AbilityHandler = (evt: KiGestureEvent) => void;

/**
 * Conecta los eventos de gestos con las habilidades del juego.
 * El diseñador de niveles instancia esto y registra handlers.
 *
 * Ejemplo de uso en un nivel:
 *   const kiComp = new KiAbilityComponent(kiSystem);
 *   kiComp.bindAbility('Kamehameha', (evt) => spawnKamehamehaBeam(evt));
 *   kiComp.bindAbility('KiBlast',    (evt) => shootKiBall(evt.origin, evt.direction));
 */
export class KiAbilityComponent {
  private bindings = new Map<KiGestureName, AbilityHandler>();
  private cooldowns = new Map<KiGestureName, number>();

  /** Cooldowns en segundos por gesto (configurable por el diseñador) */
  public cooldownMap: Record<KiGestureName, number> = {
    Kamehameha: 5,
    KiBlast:    0.3,
    Galick:     8,
    Genkidama:  30,
  };

  constructor(private kiSystem: KiHandSignaturesSystem) {
    kiSystem.onKiGestureDetected.add((evt) => this.handleGesture(evt));
  }

  /**
   * Asocia un gesto a una función de habilidad.
   * @param gesture  - Nombre del gesto ("Kamehameha", "KiBlast", etc.)
   * @param handler  - Función que recibe el evento y ejecuta el ataque
   */
  bindAbility(gesture: KiGestureName, handler: AbilityHandler): this {
    this.bindings.set(gesture, handler);
    return this;
  }

  private handleGesture(evt: KiGestureEvent): void {
    const handler = this.bindings.get(evt.gesture);
    if (!handler) return;

    const now = performance.now() / 1000;
    const lastUsed = this.cooldowns.get(evt.gesture) ?? 0;
    const cd = this.cooldownMap[evt.gesture];

    if (now - lastUsed < cd) {
      console.log(`[KiAbility] ${evt.gesture} en cooldown (${(cd - (now - lastUsed)).toFixed(1)}s restantes)`);
      return;
    }

    this.cooldowns.set(evt.gesture, now);
    handler(evt);
  }

  dispose(): void {
    this.bindings.clear();
  }
}
```

---

## Integración rápida en un nivel

```typescript
// src/levels/BattleLevel.ts
import { KiHandSignaturesSystem } from '../ki/KiHandSignaturesSystem';
import { KiAbilityComponent } from '../ki/KiAbilityComponent';
import { DEFAULT_KI_CONFIG } from '../ki/types';

async function setupKiSystem(xrHelper, scene) {
  const kiSystem = new KiHandSignaturesSystem(scene, {
    ...DEFAULT_KI_CONFIG,
    level: 3,                    // nivel 3: más sensible, más efectos
    confirmFrames: 10,           // más rápido de confirmar
    genkidamaCooldown: 20,       // cooldown reducido
  });

  const supported = await kiSystem.initialize(xrHelper);
  if (!supported) {
    showUI('⚠️ Este dispositivo no soporta hand tracking. Usa controladores.');
    return;
  }

  const kiComp = new KiAbilityComponent(kiSystem);

  kiComp.bindAbility('Kamehameha', (evt) => {
    spawnChargedBeam(evt.origin, evt.direction, evt.chargeLevel);
    playKiVFX('kamehameha', evt.origin);
  });

  kiComp.bindAbility('KiBlast', (evt) => {
    shootProjectile(evt.origin, evt.direction, { speed: 30, damage: 10 });
    playKiVFX('blast', evt.origin);
  });

  kiComp.bindAbility('Galick', (evt) => {
    spawnGalickBomb(evt.origin, evt.direction);
    playKiVFX('galick', evt.origin);
  });

  kiComp.bindAbility('Genkidama', (evt) => {
    chargeAndFireGenkidama(evt.origin);
    playKiVFX('genkidama', evt.origin);
  });
}
```

---

## Guía rápida para diseñadores de niveles

| Gesto | Pose requerida | Duración | Cooldown | Parámetro clave |
|---|---|---|---|---|
| **Kamehameha** | Ambas palmas al frente, dedos juntos | Cargado (hasta 2.5s) | 5s | `kamehamehaMaxCharge` |
| **Ki-Blast** | Índice+medio apuntando, anular recogido | Instantáneo | 0.3s | `alignmentThreshold` |
| **Galick** | Manos laterales + movimiento frontal | Breve invocación | 8s | `confirmFrames` |
| **Genkidama** | Manos elevadas sobre cabeza (3x tiempo) | Largo | 30s | `genkidamaCooldown` |

Para ajustar la sensibilidad: **baja `alignmentThreshold`** (más fácil) o **sube `confirmFrames`** (más difícil).

Lee `references/level-config.md` para la guía completa de configuración por nivel.
