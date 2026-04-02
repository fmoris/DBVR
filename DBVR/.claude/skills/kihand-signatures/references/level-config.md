# Guía de Configuración por Nivel — Diseñadores de Niveles

## Concepto

El sistema KiHand Signatures es completamente configurable sin tocar código de detección.
Como diseñador, solo necesitas:
1. Instanciar `KiHandSignaturesSystem` con la config de nivel
2. Crear un `KiAbilityComponent` y registrar tus handlers
3. Opcionalmente, modificar cooldowns en `kiComp.cooldownMap`

## Configuración por nivel de juego

```typescript
// config/ki-levels.ts
import { KiSkillConfig } from '../ki/types';

export const KI_LEVELS: Record<number, Partial<KiSkillConfig>> = {
  1: {
    // Novato — gestos muy fáciles, cooldowns reducidos
    level: 1,
    alignmentThreshold: 0.75,
    confirmFrames: 15,
    kamehamehaMaxCharge: 3.0,
    genkidamaCooldown: 45,
  },
  2: {
    level: 2,
    alignmentThreshold: 0.80,
    confirmFrames: 12,
    kamehamehaMaxCharge: 2.8,
    genkidamaCooldown: 35,
  },
  3: {
    // Estándar
    level: 3,
    alignmentThreshold: 0.85,
    confirmFrames: 10,
    kamehamehaMaxCharge: 2.5,
    genkidamaCooldown: 30,
  },
  4: {
    level: 4,
    alignmentThreshold: 0.88,
    confirmFrames: 8,
    kamehamehaMaxCharge: 2.0,
    genkidamaCooldown: 20,
  },
  5: {
    // Maestro del Ki — máxima exigencia
    level: 5,
    alignmentThreshold: 0.92,
    confirmFrames: 6,
    kamehamehaMaxCharge: 1.5,
    genkidamaCooldown: 15,
  },
};
```

## Cambio de nivel en caliente

```typescript
// El diseñador puede cambiar el nivel sin reiniciar el sistema
kiSystem.updateConfig(KI_LEVELS[newLevel]);
```

## Personalización de cooldowns por zona de nivel

```typescript
// Zona con más enemigos → cooldowns reducidos
kiComp.cooldownMap.KiBlast = 0.15;  // más rápido

// Boss final → Genkidama habilitado con cooldown reducido
kiComp.cooldownMap.Genkidama = 15;
```

## Tabla de habilidades por nivel

| Nivel | Ki-Blast | Kamehameha | Galick | Genkidama |
|---|---|---|---|---|
| 1 | ✅ 0.5s CD | ✅ Fácil de cargar | ❌ Bloqueado | ❌ Bloqueado |
| 2 | ✅ 0.4s CD | ✅ Normal | ✅ 12s CD | ❌ Bloqueado |
| 3 | ✅ 0.3s CD | ✅ Normal | ✅ 8s CD | ✅ 30s CD |
| 4 | ✅ 0.2s CD | ✅ Preciso | ✅ 6s CD | ✅ 20s CD |
| 5 | ✅ 0.15s CD | ✅ Exigente | ✅ 5s CD | ✅ 15s CD |

Para bloquear una habilidad en niveles bajos, no la registres en `KiAbilityComponent`:

```typescript
if (playerLevel >= 2) {
  kiComp.register({ gesture: 'Galick', cooldown: 8, execute: galickHandler });
}
if (playerLevel >= 3) {
  kiComp.register({ gesture: 'Genkidama', cooldown: 30, execute: genkidamaHandler });
}
```

## Debugging de gestos

Para visualizar qué está detectando el sistema durante desarrollo:

```typescript
kiSystem.onKiGestureDetected.add((evt) => {
  console.log(`[Ki] ${evt.gesture} | hand: ${evt.hand} | charge: ${evt.chargeLevel.toFixed(2)}`);
});
```

Para activar un overlay visual de articulaciones (solo en desarrollo):

```typescript
// Babylon.js renderiza las articulaciones automáticamente si se activa el display
handFeature.showHandMeshes = true; // muestra el esqueleto de la mano
```
