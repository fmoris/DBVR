# KiAbilityComponent — Patrón Component-System de Antigravity

## Arquitectura Component-System en Antigravity

Antigravity sigue un patrón ECS (Entity-Component-System) ligero sobre Babylon.js.
Cada **Component** encapsula lógica; los **Systems** coordinan componentes del mismo tipo.

```
Entity (nodo de escena / TransformNode)
 └── Component[]
      ├── KiAbilityComponent   ← escucha gestos, dispara poderes
      ├── HealthComponent
      └── AnimatorComponent
```

## KiAbilityComponent completo con animaciones

```typescript
// src/ki/KiAbilityComponent.ts
import { TransformNode } from '@babylonjs/core/Meshes/transformNode.js';
import { Scene } from '@babylonjs/core/scene.js';
import { ParticleSystem } from '@babylonjs/core/Particles/particleSystem.js';
import { Vector3 } from '@babylonjs/core/Maths/math.vector.js';
import { Color4 } from '@babylonjs/core/Maths/math.color.js';
import { MeshBuilder } from '@babylonjs/core/Meshes/meshBuilder.js';
import { KiGestureEvent, KiGestureName } from './types';
import { KiHandSignaturesSystem } from './KiHandSignaturesSystem';

export interface KiAbilityDef {
  gesture: KiGestureName;
  cooldown: number;
  /** Función del juego que ejecuta el ataque */
  execute: (evt: KiGestureEvent, owner: TransformNode) => void;
}

export class KiAbilityComponent {
  private abilities = new Map<KiGestureName, KiAbilityDef>();
  private cooldowns = new Map<KiGestureName, number>();
  private handVFX   = new Map<string, ParticleSystem>();

  constructor(
    private owner: TransformNode,
    private scene: Scene,
    private kiSystem: KiHandSignaturesSystem,
  ) {
    kiSystem.onKiGestureDetected.add((evt) => this.onGesture(evt));
  }

  /** Registra una habilidad vinculada a un gesto */
  register(def: KiAbilityDef): this {
    this.abilities.set(def.gesture, def);
    return this;
  }

  private onGesture(evt: KiGestureEvent): void {
    const def = this.abilities.get(evt.gesture);
    if (!def) return;

    const now = performance.now() / 1000;
    const last = this.cooldowns.get(evt.gesture) ?? 0;
    if (now - last < def.cooldown) return;

    this.cooldowns.set(evt.gesture, now);
    def.execute(evt, this.owner);
  }

  /** Crea partículas de Ki sobre la mano (efecto visual de carga) */
  spawnHandAura(handOrigin: Vector3, color: Color4, intensity: number): ParticleSystem {
    const key = `${handOrigin.toString()}-${color.toString()}`;
    if (this.handVFX.has(key)) return this.handVFX.get(key)!;

    const ps = new ParticleSystem('kiAura', 60 * intensity, this.scene);
    ps.emitter = handOrigin;
    ps.minSize = 0.02;
    ps.maxSize = 0.05 * intensity;
    ps.color1 = color;
    ps.color2 = new Color4(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0);
    ps.minLifeTime = 0.1;
    ps.maxLifeTime = 0.3;
    ps.emitRate = 80 * intensity;
    ps.minEmitPower = 0.1;
    ps.maxEmitPower = 0.3;
    ps.start();

    this.handVFX.set(key, ps);
    return ps;
  }

  dispose(): void {
    this.handVFX.forEach((ps) => ps.dispose());
    this.handVFX.clear();
    this.abilities.clear();
  }
}
```

## Ejemplo de uso en BattleLevel (diseñador de niveles)

```typescript
import { KiHandSignaturesSystem } from '../ki/KiHandSignaturesSystem';
import { KiAbilityComponent } from '../ki/KiAbilityComponent';
import { Color4 } from '@babylonjs/core/Maths/math.color.js';
import { Vector3 } from '@babylonjs/core/Maths/math.vector.js';

async function buildPlayer(xrHelper, scene, playerNode) {
  const kiSys = new KiHandSignaturesSystem(scene, { level: 3 });
  await kiSys.initialize(xrHelper);

  const kiComp = new KiAbilityComponent(playerNode, scene, kiSys);

  kiComp
    .register({
      gesture: 'Kamehameha',
      cooldown: 5,
      execute(evt) {
        // Proyectil cargado azul en función del chargeLevel
        const size = 0.1 + evt.chargeLevel * 0.5;
        const beam = MeshBuilder.CreateSphere('beam', { diameter: size }, scene);
        beam.position.copyFrom(evt.origin);
        // Aplicar física / impulso hacia evt.direction...
        kiComp.spawnHandAura(evt.origin, new Color4(0.2, 0.5, 1, 1), evt.chargeLevel);
      },
    })
    .register({
      gesture: 'KiBlast',
      cooldown: 0.3,
      execute(evt) {
        const ball = MeshBuilder.CreateSphere('kiBall', { diameter: 0.05 }, scene);
        ball.position.copyFrom(evt.origin);
        // Mover ball hacia evt.direction a alta velocidad...
        kiComp.spawnHandAura(evt.origin, new Color4(1, 0.8, 0, 1), 0.5);
      },
    })
    .register({
      gesture: 'Galick',
      cooldown: 8,
      execute(evt) {
        // Bomba de energía morada...
        kiComp.spawnHandAura(evt.origin, new Color4(0.6, 0, 1, 1), 0.8);
      },
    })
    .register({
      gesture: 'Genkidama',
      cooldown: 30,
      execute(evt) {
        // Gran esfera de energía, cooldown alto
        kiComp.spawnHandAura(evt.origin, new Color4(0.9, 0.95, 1, 1), 1.0);
      },
    });
}
```

## Evento OnKiGestureDetected — contrato de interfaz

```typescript
// Estructura del evento emitido por el sistema
interface KiGestureEvent {
  gesture:     KiGestureName;   // 'Kamehameha' | 'KiBlast' | 'Galick' | 'Genkidama'
  hand:        'left' | 'right' | 'both';
  chargeLevel: number;          // 0.0 – 1.0 (relevante para Kamehameha)
  origin:      Vector3;         // posición de la muñeca / punto de origen del ataque
  direction:   Vector3;         // dirección normalizada del ataque
}
```

Los sistemas de combate, animación y VFX deben suscribirse únicamente a
`kiSystem.onKiGestureDetected` y nunca al detector interno directamente.
