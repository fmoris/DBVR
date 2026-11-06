# AGENTS.md - Godot VR Game Studio Workspace

## Motor y Entorno
- **Motor:** Godot 4.3+ (Mobile / Compatibility)
- **Target:** Meta Quest OpenXR VR
- **Tracking:** OpenXR Hand Tracking (26 huesos) vía XRHandModifier3D

## 🚨 REGLAS CRÍTICAS DE EJECUCIÓN
- **Tipado Estático Estricto:** Siempre tipar variables y retornos en GDScript 2.0.
- **Delta en Física:** Multiplicar por delta en _physics_process(delta).
- **Rutas OpenXR:** Rutas canónicas /user/hand_tracker/left y /user/hand_tracker/right.
- **Modelos GLB y Escala:** Huesos con nombres OpenXR estándar (LeftWrist, etc.) y escala métrica 1.0 en runtime.

## Roles del Estudio Disponibles
- /godot-engine-specialist: OpenXR, shaders y GDScript.
- /game-design-system: Especificación de mecánicas y balance.
- /game-dev-story: Programación de sistemas y nodos.
- /game-code-review: Revisión de fugas de memoria y ciclo de vida de nodos.
