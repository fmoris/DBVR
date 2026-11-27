# AGENTS.md - DBZVR Godot VR Game Studio Workspace

## Motor y Entorno
- **Motor:** Godot 4.3+ / 4.8 (Mobile / Compatibility)
- **Target:** Meta Quest 3 OpenXR VR (90 FPS estables)
- **Tracking:** OpenXR Hand Tracking (26 huesos) vía `XRHandModifier3D`
- **Godot CLI Headless:** siempre pasar `--xr-mode off` (`--headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3`)

---

## 🚨 REGLAS CRÍTICAS DE EJECUCIÓN
- **SIEMPRE INSPECCIONAR CONSOLA Y LOGS TRAS CADA EDICIÓN:**
  - Tras modificar código GDScript, shaders o escenas, inspeccionar activamente la consola de Godot (`--headless --xr-mode off` / `--check-only`) para confirmar **0 errores de compilación, parsing ni runtime**.
- **Protocolo Anti-Iteración (Menos Vueltas, Cero Regresiones):**
  - **Enrutamiento obligatorio por Squad:** antes de editar cualquier archivo, identificar el Squad dueño en la tabla inferior y leer su ficha en `.agents/squads/<squad>.md`. Respetar estrictamente sus fronteras de archivos.
  - **Preview de escritorio antes que APK:** todo ajuste visual, de animaciones, de rigging o de UI debe probarse primero en escritorio con `& "d:\Mis Documentos\dbzvr\run_desktop_preview.ps1"` (`zenkai_showcase.tscn` o `-Arena`) antes de compilar un APK de 175 MB.
  - **Cero soluciones inventadas/híbridas:** si un asset, extractor o formato binario está incompleto o falla, **detenerse, reportar el estado exacto y preguntar al usuario cómo continuar**. Prohibido mezclar silenciosamente código procedural viejo con assets nuevos.
- **Flujo Git-Flow Estricto:**
  - `main`: **SOLO código probado y validado empíricamente en el visor VR**.
  - `develop`: Rama base para integración continua y desarrollo.
  - Ramas `feature/*` o `fix/*`: trabajar siempre sobre rama dedicada desde `develop`. Al terminar y verificar un ciclo, hacer `git add` + `git commit` + `git push` a `origin`.
- **Calidad GDScript 2.0:**
  - Tipado estático estricto (`func test() -> void:`), multiplicar física por `delta` en `_physics_process(delta)` y **zero allocations** en hot paths.
  - Rutas OpenXR canónicas: `/user/hand_tracker/left` y `/user/hand_tracker/right`. Escala métrica 1:1 en runtime.
- **Compilación APK Fuera del Chat (0 Tokens) y Autorización Obligatoria para Envío a los Lentes:**
  - El agente **NO** compila `builds/dbzvr.apk` ni ejecuta `adb install` dentro del chat (ahorro de tokens y tiempo de espera).
  - En lugar de ejecutar el build en el chat, cuando un cambio esté listo para probar en Meta Quest 3 (o si el usuario pide generar el APK), el agente debe **entregarle la ruta/comando directo y la opción de dispararlo**:
    1. **Manual (0 tokens):** doble clic en `d:\Mis Documentos\dbzvr\build_apk.bat` o ejecutar `& "d:\Mis Documentos\dbzvr\build_apk.ps1"`.
    2. **Automático por hook:** ofrecer cerrar un `git commit` con el marcador `[apk]` para que `.agents/hooks.json` abra automáticamente la ventana independiente de Windows (`build_apk.ps1` + parada de Gradle daemon + confirmación interactiva `[S/N]` de `adb install`).
  - **NUNCA** desplegar ni instalar el APK en los lentes sin autorización explícita del usuario. Cuando autorice, verificar `adb devices` primero.
- **Informe Final Obligatorio:** concluir cada ciclo explicando qué cambió, dónde, por qué y la validación empírica realizada.
- **Destilación Automática de Aprendizajes (Cero Regresiones Futuras):** cada vez que se descubra y resuelva un bug no trivial, una trampa de Godot/OpenXR o una nueva invariante de arquitectura, registrarla de inmediato en la sección `Invariantes Críticas` del Squad dueño (`.agents/squads/<squad>.md`) y en la memoria de sesión (`d:\openclaw\workspace\memory\YYYY-MM-DD.md` / `MEMORY.md`).
- **Ahorro de Tokens y Recordatorio Proactivo de Contexto:** al cerrar un hito/commit/APK, después de sesiones con muchas lecturas/imágenes o al detectar un cambio de Squad/dominio, recordar proactivamente al usuario cuándo conviene usar `/compact` (si sigue sobre el mismo bloque), cuándo abrir un chat nuevo (si cambia de dominio) y sugerir validar en Godot headless/escritorio y agrupar cambios en lote antes de compilar APK cuando ahorre tokens y tiempo.

---

## 🎯 ROUTER CANÓNICO DE SQUADS ESPECIALIZADOS (`.agents/squads/`)

Cada dominio del juego tiene un Squad dueño de sus archivos y sus skills (curadas a 51 skills activas en `.agents/skills/`; las no aplicables están archivadas en `.agents/skills_archive/`):

| ID | Squad | Ficha | Dominio / Archivos Propios | Skills Clave |
|---|---|---|---|---|
| **1A** | `melee-squad` | [1a-melee-sequences.md](squads/1a-melee-sequences.md) | `MeleeTargetDome.gd`, `FollowUpSequenceController.gd`, `MeleeLoreEventController.gd`, `HybridCombatController.gd` (melee/desvío/dash) | `godot-genre-fighting`, `godot-combat-system`, `state-machine`, `physics-system` |
| **1B** | `super-beam-squad` | [1b-super-beams.md](squads/1b-super-beams.md) | `SuperBeamSequenceController.gd`, `BeamClashController.gd`, `ProceduralKiProjectile.gd` | `godot-combat-system`, `godot-signal-architecture`, `tween-animation`, `godot-raycasting-queries` |
| **2** | `ki-bp-systems` | [2-ki-bp-systems.md](squads/2-ki-bp-systems.md) | `character_instance.gd` (Ki/NP/Furia/Zenkai), `CombatAIController.gd`, `DramaticDirector.gd`, `vr_hud.gd` | `godot-state-machine-advanced`, `godot-signal-architecture`, `godot-gdscript-mastery`, `game-ui-specialist` |
| **3A** | `xr-gestures` | [3a-xr-gestures.md](squads/3a-xr-gestures.md) | `GesturePhaseTree.gd`, `xr_setup.gd`, `ki_sense_and_lockon.gd`, OpenXR 26 joints | `xr-development`, `godot-platform-vr`, `gdscript-advanced` |
| **3B** | `character-animations` | [3b-character-animations.md](squads/3b-character-animations.md) | `ProceduralCombatAnimator.gd`, `ZenkaiAnimationLoader.gd`, `runtime_ragdoll_generator.gd`, `skeleton_axis_calibration.json` | `animation-system`, `godot-animation`, `godot-physics-3d`, `godot-gdscript-mastery` |
| **4A** | `vfx-shaders` | [4a-vfx-shaders.md](squads/4a-vfx-shaders.md) | `ZenkaiVFXManager.gd`, `KiSmokeFX.gd`, `shaders/*.gdshader`, `assets/vfx_zenkai/`, aura | `godot-shader-vfx-library`, `shader-basics`, `particles-vfx`, `rendering-pipeline`, `godot-polish` |
| **4B** | `audio-voices` | [4b-audio-voices.md](squads/4b-audio-voices.md) | `AudioActionManager.gd`, `assets/audio/audio_actions.json`, bancos Zenkai | `audio-system`, `godot-audio`, `gdscript-advanced` |
| **5** | `environment-arena` | [5-environment-arena.md](squads/5-environment-arena.md) | `cell_games_arena.tscn`, `build_arena.gd`, `ArenaDestructionManager.gd` | `3d-essentials`, `rendering-pipeline`, `physics-system`, `godot-performance-optimization` |
| **6** | `lore-balance` | [6-lore-balance.md](squads/6-lore-balance.md) | `resources/*.tres`, `scripts/resources/*.gd` (Goku/Vegeta canon, NP, transformaciones) | `resource-pattern`, `godot-resource-data-patterns`, `godot-director`, `godot-distiller` |
| **7** | `qa-release-ops` | [7-qa-release-ops.md](squads/7-qa-release-ops.md) | `zenkai_showcase.tscn`, `ZenkaiShowcaseViewer.gd`, `run_desktop_preview.ps1`, `build_apk.ps1`, `build_apk.bat`, `.agents/hooks.json`, `CombatSequenceRunner.gd`, `FEATURE_MAP.md` | `godot-headless-workflow`, `godot-auditor`, `godot-code-review`, `mobile-development`, `export-pipeline` |

### Coordinación entre Squads
- Si una tarea cruza dos dominios (por ejemplo, un nuevo Súper Ataque requiere secuencia en `1B`, VFX en `4A` y sonido en `4B`), definir primero el **contrato de interfaz** (nombre de método/señal o `action_id`) y ejecutar cada Squad sobre sus propios archivos (en serie o en paralelo con `/teamwork`).
