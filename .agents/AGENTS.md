# AGENTS.md - Godot VR Game Studio Workspace

## Motor y Entorno
- **Motor:** Godot 4.3+ (Mobile / Compatibility)
- **Target:** Meta Quest OpenXR VR (90 FPS estables)
- **Tracking:** OpenXR Hand Tracking (26 huesos) vía XRHandModifier3D

---

## 🚨 REGLAS CRÍTICAS DE EJECUCIÓN
- **SIEMPRE INSPECCIONAR CONSOLA Y LOGS TRAS CADA EDICIÓN:**
  - Tras modificar código GDScript, shaders o escenas, inspeccionar activamente la consola de Godot (vía headless check `--check-only` o logs) para confirmar que **NO existen errores de compilación, de parsing ni excepciones en consola**.
  - Nunca dar por terminada una tarea sin haber verificado empíricamente la consola de Godot.
- **Flujo Git-Flow Estricto:**
  - `main`: **SOLO código probado y validado empíricamente en el visor VR**.
  - `develop`: Rama base para integración continua y desarrollo de nuevas funcionalidades.
  - Ramas `feature/*`: Para tareas específicas (ej. nuevas mecánicas, poderes o shaders).
  - Al terminar una tarea, se prueba y valida en APK antes de promocionar o mergear a `main`.
- **Tipado Estático Estricto:** Siempre tipar variables y retornos en GDScript 2.0 (`func test() -> void:`).
- **Delta en Física:** Multiplicar por delta en `_physics_process(delta)`.
- **Rutas OpenXR:** Rutas canónicas `/user/hand_tracker/left` y `/user/hand_tracker/right`.
- **Modelos GLB y Escala:** Huesos con nombres OpenXR estándar (`LeftWrist`, etc.) y escala métrica 1.0 en runtime.
- **Zero Allocations en Hot Paths:** Prohibido instanciar arrays/diccionarios en `_process` o `_physics_process`.

---

## 🎭 MATRIZ CANÓNICA DE ROLES Y SKILLS ASIGNADAS

Cada rol del estudio tiene asignado un núcleo de skills especializadas que debe cargar y consultar activamente antes de diseñar, programar o auditar código:

### 1. `/godot-engine-specialist` (Godot & OpenXR Architect)
* **Misión:** Arquitectura del motor, ciclo de vida de nodos, hand tracking y despliegue en Quest.
* **Skills Asignadas:**
  - `xr-development`: OpenXR, XROrigin3D, Hand Tracking (26 joints), Meta Quest passthrough.
  - `godot-platform-vr`: Reglas para 90 FPS estables, foveated rendering y prevención de cinetosis.
  - `mobile-development`: Exportación APK, ASTC compresión y optimización de batería en Quest.
  - `3d-essentials` & `physics-system`: Colisiones 3D, CharacterBody3D y queries de raycasting.
  - `gdscript-advanced` & `gdscript-mastery`: GDScript 2.0 estático, Callable binds y zero-allocations.
  - `godot-meta-toolkit`: Integración de plataforma Meta Quest (si aplica).

### 2. `/technical-artist` (Shaders, Materiales Anime & VFX)
* **Misión:** Cel-shading anime de Dragon Ball, auras de Ki, partículas GPU y estética visual fiel al manga/anime sin penalizar el framerate.
* **Skills Asignadas:**
  - `godot-shader-vfx-library`: Shaders listos para Cel-Shading, contornos 3D, shockwaves, auras y hologramas.
  - `shader-basics` & `godot-shaders-vfx`: Shaders espaciales y canvas para renderizador Compatibility/Mobile.
  - `particles-vfx`: GPUParticles3D, pooling y optimización para la GPU Adreno de Meta Quest.
  - `rendering-pipeline`: Balance de MSAA, resolución dinámica y budget de dibujo por ojo.
  - `godot-effects` & `godot-polish`: Feedback visual de impactos, distorsión de aire y destellos.

### 3. `/game-design-system` & `/gameplay-programmer` (Combate & Mecánicas Canon)
* **Misión:** Implementación de mecánicas gestuales, árbol de combos, Nivel de Poder (NP) y combate biométrico 1v1.
* **Skills Asignadas:**
  - `godot-genre-fighting`: Lógica de combate 1v1, hitboxes/hurtboxes, frames de invencibilidad y buffers de reacción.
  - `godot-combat-system`: Sistemas de cálculo de daño, estados de aturdimiento y cadenas de golpes.
  - `state-machine` & `godot-state-machine-advanced`: FSM jerárquica (Fase Libre vs Fase de Cadena, Furia, Zenkai).
  - `resource-pattern`: Custom Resources para técnicas, multiplicadores de daño y umbrales de NP.
  - `godot-signal-architecture`: Arquitectura desacoplada ("Signal Up, Call Down").
  - `godot-xr-gesture-trie`: Motor gestual Trie para reconocimiento de gestos (Kamehameha, Ki Blast, Recarga de Ki).

### 4. `/game-code-review` / `godot-auditor` (QA, Profiling & Headless Checks)
* **Misión:** Inspección continua de consola, erradicación de fugas de memoria y garantía de estabilidad.
* **Skills Asignadas:**
  - `godot-headless-workflow`: Validación CLI con `--check-only` sin abrir GUI tras cada edición de código.
  - `godot-auditor`: Detección de fugas (`queue_free()` vs `free()`), señales huérfanas y anti-patrones.
  - `godot-debugging` & `godot-performance`: Profiling de frametime, reducción de draw calls y diagnóstico de excepciones.
  - `godot-performance-optimization`: Optimizaciones extremas de memoria y mallas.

### 5. `/game-studio-director` (Director Creativo & Scaffolding)
* **Misión:** Planificación de hitos, alcance de sesiones y generación asistida de escenas.
* **Skills Asignadas:**
  - `godot-director` & `godot-distiller`: Desglose del GDD y acotación de entregables por sesión.
  - `godot-builder` & `godot-scene-arch`: Scaffolding y composición limpia de escenas.
  - `godot-analyst`: Scoring de salud de proyecto y grafo de dependencias de escenas.
