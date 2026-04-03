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
- **Detección de Manos:** Refactorizado `GestureRecognizer` para usar la API W3C joints por nombre (Quest 3 compatible).
- **HUD VR:** Creación de `VRHud.ts` usando AdvancedDynamicTexture de Babylon para mostrar NP/KI en planos 3D atados a la cabeza.
- **Diseño Refinado:** Codificación de la "Ciencia del Juego" en `DESIGN.md` (NP, Cadenas de Melee, Super Poderes de 2 pasos).
- **Victoria y Comeback:** Definición de 3 rutas de victoria y mecánicas de remontada.

## Lecciones Aprendidas
- **Z-Index en WebXR:** El overlay del DOM para VR requiere `position: fixed` y `pointer-events: none` por defecto para no bloquear la interacción 3D o en el menú.
- **Joints de Manos:** Nunca confiar en los índices numéricos de los joints; siempre usar los nombres W3C (`THUMB_METACARPAL`, etc.) para máxima compatibilidad entre headsets.
- **Diferencial de Poder:** La mecánica de NP (0-100) donde la victoria ocurre con una diferencia de 50 puntos crea una tensión dramática fiel al anime.

## Próximos Pasos (Meta-Nivel)
1. **Parte 2: Combate Melee.** Transición a cámara lenta al activarse, sombras de golpes para el defensor, detección de puntos de impacto.
2. **Audio Canon:** Canto de técnicas, música de batalla dinámica, efectos de sonido de carga de Ki.
3. **Escenarios:** Mejorar la fidelidad de los escenarios (fuego, cráteres, destrucción).
4. **Skills de Agente:** Integrar y ampliar el sistema de habilidades en `.agents/skills`.
