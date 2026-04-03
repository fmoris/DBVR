# DESIGN.md - Dragon Ball VR: Power Clash

## 1. Visión General del Juego

**Título provisional:** Dragon Ball VR: Power Clash  
**Género:** Pelea 1vs1 en tiempo real con elementos de rol  
**Plataforma:** WebXR (Meta Quest 3 + PC VR)  
**Motor:** Babylon.js + WebXR Hand Tracking  
**Estilo visual:** Cel-shaded / anime 3D inspirado en Dragon Ball (estilo Budokai Tenkaichi + animación fluida)  
**Duración de una pelea:** 2 a 5 minutos (intensa y cinematográfica)

El juego es una experiencia de peleas **sin turnos** donde la velocidad de reacción, la gestión inteligente de recursos (KI y NP) y la ejecución de gestos son clave.

## 2. Inspiración Principal

- **Yu Yu Hakusho: Tokubetsu Hen (SNES)** → Combate en tiempo real donde el atacante lanza primero y el defensor tiene segundos para reaccionar.
- **Dragon Ball (anime/manga)** → Gestión de KI, Nivel de Poder (NP), comebacks épicos, bullet-time en peleas cercanas, cadenas de golpes cuerpo a cuerpo y choques de poder.

## 3. Mecánicas Core

### 3.1 Gestión de KI
Recurso principal y limitado. Se consume en ataques y defensas. Cuanto más KI se invierta, mayor potencia, velocidad o duración tiene la acción. Se regenera lentamente con el tiempo y más rápido al recibir daño (resistencia).

### 3.2 Nivel de Poder (NP)
Valor numérico (0-100 %) que representa el poder actual del personaje.  
- Comienza con un **valor base** diferente por cada personaje.  
- Sube durante la pelea según acciones exitosas y resistencia.  
- **Niveles irreversibles**: una vez alcanzado 25 %, 50 %, 75 % o 100 %, no puede bajar de ese umbral.

### 3.3 Fórmula de Nivel de Poder (NP) – Propuesta inicial
Para que sea **entretenida y refleje el alma de Dragon Ball**:

**Ganancia básica de NP:**
- NP Ganado = (Daño infligido × Multiplicador KI) + Bonus Momentum + Bonus Resistencia

**Multiplicadores clave:**
- Ataque Rápido KI: ×1.2 (impacto) / ×1.8 (3 impactos seguidos)
- Ataque Cargado KI: ×1.6
- Super Poder: ×2.5 (si se carga completo)
- Recibir daño y bloquear bien: +0.8–1.5 (según calidad de defensa)
- Comeback (NP rival ≥ 30 % por encima): ×2.0 multiplicador extra al defensor

**Pérdida de NP:**
- Solo ocurre en casos muy específicos (desvío exitoso o choque de poder perdido). Nunca baja de un nivel irreversible.

## 4. Sistema de Combate – Cadenas y Bullet-Time

El combate combina **cadenas de melee** y **ataques de KI** en un flujo dinámico y cinematográfico.

Cuando un jugador inicia un ataque, su personaje se lanza hacia el rival y se activa **bullet-time** (cámara lenta) al acercarse, dando a ambos jugadores tiempo para reaccionar con gestos de manos.

### 4.1 Cadenas de Melee

1. El atacante lanza un ataque melee → su personaje sale disparado hacia el defensor.
2. Al llegar al defensor se activa **bullet-time** (aprox. 0.3x velocidad). Ambos tienen **1.5–2 segundos** para elegir acción mediante gestos.
3. **Opciones del Atacante (Melee):**
   - **Ataque Rápido**: ventana de respuesta corta, bajo consumo de KI.
   - **Ataque Múltiple**: varios golpes seguidos. El defensor debe bloquear al menos el 51 % para no perder el control de la cadena.
   - **Ataque Cargado**: lanza lejos al defensor y puede encadenarse con un ataque de KI o superataque.
   - **Ataque Desvanecedor**: el atacante desaparece y reaparece en uno de los 4 puntos cardinales del defensor. El defensor debe girarse rápidamente para defenderse.

4. **Opciones del Defensor:**
   - **Bloqueo Total**: gasta KI, no rompe la cadena.
   - **Bloqueo Predictivo**: adivinar la zona del golpe → contraataque exitoso (se invierten los roles).
   - **Esquiva**: gasta más KI, rompe la cadena y da ventaja posicional.

Si el defensor falla repetidamente, la cadena continúa y el atacante gana momentum y NP.

### 4.2 Ataques de KI

Existen **3 tipos** de ataques de KI:

| Tipo                  | Gasto KI          | Velocidad | NP Generado     | Notas especiales |
|-----------------------|-------------------|-----------|-----------------|------------------|
| **Ataque Rápido**     | Gradual y bajo    | Muy rápido| Medio-alto      | Si impacta 3 veces seguidas → activa cadena (melee o super con ventaja) |
| **Ataque Cargado**    | Medio             | Rápido    | Alto            | Genera más NP y empieza cadena automáticamente |
| **Super Poder**       | Alto              | Lento     | Muy alto        | Requiere **carga mínima** + mantenimiento. Usa **2 gestos**: (1) gesto de carga, (2) gesto de lanzamiento. Si se lanza antes del tiempo mínimo → falla |

**Mecánica de Super Poder:**
- El jugador debe mantener el gesto de carga durante X segundos (depende del personaje y poder).
- Luego realiza el gesto de lanzamiento.
- Solo se ejecuta si se completó el tiempo mínimo de carga.

### 4.3 Defensas contra Super Ataques de KI

El defensor tiene **3 opciones** cuando recibe un super ataque:

1. **Bloqueo Normal**  
   - No gasta KI.  
   - Sube NP del defensor (resistencia).  
   - El atacante gana **más** NP (dominio).

2. **Desvío** (difícil, requiere timing y gesto preciso)  
   - Genera **mucho** NP al defensor.  
   - Baja NP del atacante.  
   - El ataque se redirige (puede incluso golpear al atacante).

3. **Choque de Poder**  
   - Ambos lanzan un super ataque simultáneamente.  
   - Se inicia un mini-juego de choque donde el KI de ambos baja rápidamente.  
   - **Ventaja**: el jugador con mayor NP actual recibe bonus (más daño, menos pérdida de KI).  
   - El perdedor recibe el golpe completo y el ganador obtiene **gran cantidad** de NP.

## 5. Condiciones de Victoria y Ataque Final

Existen **tres caminos** para activar el **Movimiento Final**:

1. **Diferencia notable de NP** (ej: +35 % de ventaja).
2. **Llegar al tope de NP** (100 %).
3. **Comeback exitoso** (NP sube drásticamente después de estar en desventaja).

Al cumplir una o más condiciones:
- El jugador puede ejecutar su **Poder Final** (movimiento canon o exclusivo).
- El defensor tiene **una última oportunidad** de salvarse con un bloqueo perfecto o contra-gesto.
- Si falla → derrota épica.
- Si logra salvarse → posible activación de comeback del defensor.

## 6. Controles (WebXR Hand Tracking)

- Todos los ataques, defensas, cargas y lanzamientos se ejecutan mediante **gestos reales** de manos.
- El bullet-time permite al jugador tener tiempo suficiente para realizar gestos complejos (incluyendo carga + lanzamiento).

## 7. Pendientes / Secciones a expandir

- Lista completa de personajes y sus valores base de NP/KI.
- Tabla detallada de gestos (JSON) para cada tipo de ataque y defensa.
- Sistema de progresión entre peleas.
- UI / HUD (barras de KI y NP, indicador visual de carga de superataques, momentum).
- Balanceo numérico exacto de la fórmula de NP.
- Mecánica precisa del comeback.
