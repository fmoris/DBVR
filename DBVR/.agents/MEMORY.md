# MEMORY.md — DBVR Long-Term Memory

Recuerdos curados de DBVR (Dragon Ball VR).

## Resumen del Proyecto: Dragon Ball VR: Power Clash
- Juego de combate VR inspirado en Dragon Ball.
- Utiliza **BabylonJS** para el motor 3D y **WebXR** para el seguimiento de manos (Hand Tracking).
- **Sistema de Nivel de Poder (NP)**: Reemplaza al HP. Escala 10k-100k. Inmersión visual (sin números). Condición de victoria por brecha (35k).
- **Combate Melee**: Flujo definido en `DESIGN.md` (Ataque -> Bullet-time -> Cadena).
- **Super Poderes**: Mecánica de 2 pasos (Carga + Lanzamiento).
- **WebXR (Quest 3)**: HUD 3D world-space y hand tracking calibrado.
- El sistema de combate es "Acción-Reacción" (sin turnos, pero con ventanas de respuesta).

## Hitos Alcanzados (Resumen)
- **Fase Inicial:** Configuración de Vite/TS, escena básica, tRPC, base de datos Drizzle, servidor con replay en S3.
- **Gestos de Ki:** Implementación de Kamehameha, Final Flash y Ataque Básico (GestureType).
- **WebXR (Quest 3):** Solución de problemas críticos de visualización de HUD/Overlay en VR mediante `dom-overlay`.
- **Hito GSS:** Migración completa del motor de gestos a `GestureSkillSystem` (GSS) basado en KNN. Eliminación de código heurístico legacy.
- **Entrenamiento 3D:** Implementación de persistencia sesión-por-sesión (historia 3D) en `localStorage`, permitiendo calibración personal robusta.
- **Validación de Datos:** Sistema de purga automática de datos antiguos (1152 features) para asegurar compatibilidad con el estándar actual (16/46 features).

## Lecciones Aprendidas
- **Z-Index en WebXR:** El overlay del DOM para VR requiere `position: fixed` y `pointer-events: none` por defecto para no bloquear la interacción 3D o en el menú.
- **Features Estándar:** El sistema funciona mejor con vectores fijos: **16 features** para movimientos de Ki (`wristOnly`) y **46 features** cuando la forma de la mano importa (`wristAndFingertips`).
- **Data Augmentation:** El mirroring y jittering son esenciales para que gestos entrenados con una sola mano funcionen en ambas y sean tolerantes al ruido.

## Próximos Pasos (Meta-Nivel)
1. **Parte 2: Combate Melee.** Transición a cámara lenta al activarse, sombras de golpes para el defensor, detección de puntos de impacto.
2. **Audio Canon:** Canto de técnicas, música de batalla dinámica, efectos de sonido de carga de Ki.
3. **Escenarios:** Mejorar la fidelidad de los escenarios (fuego, cráteres, destrucción).
4. **Skills de Agente:** Integrar y ampliar el sistema de habilidades en `.agents/skills`.
