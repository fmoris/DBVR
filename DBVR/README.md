# Dragon Ball VR: Power Clash

Juego de Realidad Virtual en primera persona con combates basados en el sistema de acción-reacción de **Yu Yu Hakusho: Tokubetsu Hen**. Experiencia de peleas **sin turnos** donde la velocidad de reacción y la gestión de recursos (KI y NP) son clave. Desarrollado con **TypeScript**, **Vite** y **BabylonJS** para WebXR.

## 🎮 Características del MVP

- **Combate Acción-Reacción:** Sistema táctico donde el atacante actúa y el defensor tiene tiempo para reaccionar
- **Cámara Lenta (Bullet Time):** Al recibir un ataque, la escena se ralentiza para permitir la reacción
- **Detección de Movimientos:** Seguimiento de brazos y manos mediante WebXR Hand Tracking
- **Gestión de KI:** Sistema de energía que limita las acciones ofensivas y defensivas
- **Efectos Visuales:** Proyectiles de energía con partículas y efectos de brillo

## 🛠️ Tecnología

| Tecnología | Propósito |
| :--- | :--- |
| **TypeScript** | Lenguaje principal con tipado estático |
| **Vite** | Bundler y servidor de desarrollo |
| **BabylonJS** | Motor gráfico 3D y WebXR |
| **WebXR** | API para VR y hand tracking |

## 📁 Estructura del Proyecto

```
src/
├── main.ts                 # Punto de entrada y loop principal
├── types.ts                # Tipos y enums del juego
└── systems/
    ├── CombatStateManager.ts   # Máquina de estados del combate
    ├── GestureRecognizer.ts    # Detección de gestos de manos
    ├── PlayerStats.ts          # Gestión de NP (Nivel de Poder) y KI
    ├── VFXManager.ts           # Efectos visuales y proyectiles
    └── WebXRManager.ts         # Gestión de WebXR y hand tracking
```

## 🚀 Instalación y Desarrollo

### Requisitos
- Node.js 18+
- npm o pnpm

### Instalación

```bash
# Instalar dependencias
pnpm install

# Iniciar servidor de desarrollo
pnpm dev

# Construir para producción
pnpm build
```

## 🎯 Controles (Testing sin VR)

| Tecla | Acción |
| :--- | :--- |
| **A** | Lanzar ataque |
| **S** | Bloquear |
| **R** | Recargar KI |
| **Click** | Entrar en VR |

## 🎮 Controles VR (Con Meta Quest)

- **Cargar/Lanzar Super Poder:** Gesto de carga (mantener) + Gesto de lanzamiento
- **Bloquear:** Cruzar los brazos frente al pecho
- **Recargar KI:** Brazos a los lados con puños cerrados

## 🔧 Sistemas Principales

### CombatStateManager
Controla los estados del combate:
- `NEUTRAL` - Estado inicial
- `ATTACKING` - Ejecutando ataque
- `DEFENDING` - Modo defensa activo
- `SLOW_MOTION` - Cámara lenta activada
- `HIT` - Impacto recibido

### GestureRecognizer
Detecta gestos basado en 25 puntos de articulación por mano:
- Carga de ataque (manos juntas)
- Ataque (manos empujadas)
- Bloqueo (brazos cruzados)
- Recarga (brazos a los lados)

### PlayerStats
Gestiona recursos del jugador:
- KI (0-100) con regeneración automática
- Consumo de KI por acciones

### VFXManager
Crea y gestiona:
- Proyectiles de energía con mesh y partículas
- Sistemas de partículas radiantes
- Efectos de impacto

## 📊 Sistema de Energía (KI) y NP

| Acción | Gasto KI | NP Generado | Efecto |
| :--- | :--- | :--- | :--- |
| Ataque Rápido | Bajo (Gradual) | Medio-Alto | Puede activar cadena de melee |
| Ataque Cargado | Medio | Alto | Empieza cadena automáticamente |
| Super Poder | Alto | Muy Alto | Requiere carga mínima (2 pasos) |
| Bloqueo | 15 | Sube NP (Def) | Mitiga daño, otorga NP al atacante |
| Desvío | Bajo | Muy Alto | Timing preciso, baja NP al atacante |

## 🎨 Especificaciones Visuales

- **Perspectiva:** Primera persona
- **Proyectiles:** Esferas azul eléctrico con aura luminosa
- **Interfaz:** HUD futurista en la parte inferior
- **Entorno:** Cielo dinámico y terreno abierto

## 📝 Próximos Pasos

- [ ] Implementar IA del enemigo
- [ ] Agregar más tipos de ataques (Kamehameha, etc.)
- [ ] Sistema de combos
- [ ] Múltiples escenarios
- [ ] Sonido y música
- [ ] Sistema de progresión

## 📄 Licencia

MIT
