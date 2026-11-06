---
name: game-ui-specialist
description: Especialista en diseño e implementación de interfaces, HUDs y sistemas diegéticos inmersivos en VR para Dragon Ball (Scouters, hologramas en muñeca, medidores de Ki/NP, barras de energía anime y alertas de combate).
---

# Game UI Specialist - VR Dragon Ball Interface & HUD

Usa esta skill para diseñar e implementar cualquier interfaz de usuario (HUD, menús diegéticos, Scouters, indicadores de combate, diales y feedback visual) en experiencias de realidad virtual de Dragon Ball.

## Pilares de Diseño UI/UX para VR y Dragon Ball
1. **Inmersión Diegética (Cero Fatiga en VR):**
   - Prohibido anclar elementos 2D fijos pegados al lente del visor que causan náusea o desalineación de vergencia.
   - Usar interfaces situadas en el espacio 3D (Spatial UI) o ancladas a partes del cuerpo (ej: Holo-Scouter en la muñeca izquierda del combatiente).
   - Ángulo ergonómico de lectura: visualización cómoda y natural al girar el antebrazo hacia el rostro ($35^\circ$ - $45^\circ$).
2. **Estética Auténtica Dragon Ball / Akira Toriyama:**
   - **Estilo Scouter:** Tipografía digital sci-fi anime, paleta verde esmeralda cian / ámbar Saiyajin / rojo Furia, corchetes angulares `[ ]`, retículas de fijación de objetivo y lecturas numéricas de BP (Battle Power / Nivel de Poder).
   - **Barras de Ki de Energía Viva:** Bisel metálico oscuro, relleno degradado con pulso y partículas de Ki, indicando el costo de las técnicas.
   - **Indicadores de Umbrales Irreversibles:** Muescas de bloqueo en 25%, 50%, 75% y 100% de NP.
   - **Estado Zenkai / Furia:** Pulso flamígero y alerta visual cuando el Finisher de K.O. está disponible.
3. **Rendimiento Quest 3 (Mobile VR):**
   - Uso de `SubViewport` optimizado con `render_target_update_mode = UPDATE_WHEN_VISIBLE`.
   - Shaders procedurales eficientes para diales y barras sin sobrecargar memoria de texturas.
   - Event-Driven: reactividad pura ante señales (`stats_changed`, `phase_changed`, etc.).
