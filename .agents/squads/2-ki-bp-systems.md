# Squad 2 — Economía de Ki, BP/NP, Estados e IA (`ki-bp-systems`)

## Misión
Administrar el núcleo de reglas de combate sin barra de HP: Ki, Nivel de Poder (NP) con umbrales irreversibles (25/50/75/100%), Furia, Estado Zenkai, Transformaciones, IA reactiva 1v1, dirección dramática y HUD diegético.

## Propiedad Exclusiva de Archivos
- `scripts/character_instance.gd` (lógica de stats, Ki, NP, Furia, Zenkai, transformaciones y daños)
- `scripts/CombatAIController.gd`
- `scripts/DramaticDirector.gd`
- `scripts/DramaticMiniSceneController.gd`
- `scripts/vr_hud.gd` & `vr_hud.tscn`
- `scripts/MatchResultScreen.gd` & `scripts/vr_in_game_menu.gd`

## Fronteras (NO modificar directamente)
- **NO** duplicar lógica de gestos biométricos (`3a-xr-gestures`).
- **NO** implementar shaders ni emisores de humo/explosión locales (`4a-vfx-shaders`).
- **NO** modificar poses esqueléticas (`3b-character-animations`).

## Skills Asignadas
- `godot-state-machine-advanced`
- `godot-signal-architecture`
- `godot-gdscript-mastery`
- `game-ui-specialist`
- `hud-system`

## Invariantes Críticas
- Arquitectura estricta **Signal Up, Call Down**: el combate emite señales; `vr_hud.gd` solo escucha.
- Los umbrales de NP (25/50/75/100%) son irreversibles una vez alcanzados.
- Las técnicas desbloqueadas en una transformación se heredan en todas las formas posteriores.
- **Ki Máximo Escalable por Transformación:** usar `get_max_ki()` (`base_ki + ki_max_bonus`: 100 Base ➔ 130/160/190/220 según forma) en vez de leer `character_data.base_ki` directamente en regeneración, HUD y límites de cúpula/IA; `revert_to_base()` debe clampear `current_ki` al tope activo.
- **Restauración al Transformar vs Limit Break:** `transform_to()` suma `ki_transform_restore` (`+25..+45 Ki`) únicamente si `not _is_limit_break_running`, para que el Despertar Límite automático otorgue exclusivamente su `+10 Ki` canónico.
- **Estados Indefensos Post-Lanzamiento (`VulnerabilityState`):** distinguir `AIRBORNE_LAUNCHED` (intenta Air Brake para pasar a `STABILIZED`) de `CRASHED_STAMPED` (estampado contra suelo/pilar/cordillera, sin despertar aéreo, duración `1.05s–3.40s` pausada durante `HITSTOP`/`DECISION_WINDOW`). El bono `+18 Ki` al estampar (`followup_crash_ki_bonus`) se otorga **como máximo una vez** por lanzamiento (`_crash_bonus_awarded_this_launch`).
- **Desacople total entre `0 Ki` y Zenkai/K.O.:** quedarse sin Ki (`current_ki <= 0`) nunca termina el combate (`def_exhausted_ko`, `"Agotamiento Vital"` y K.O. por `ki_break_launch` / Ki Blast cargado deshabilitados). Dominio Zenkai requiere brecha `>= 40%` BP + progresión real (`current_transformation != null` o `current_np >= active_max * 0.70` en Base), y `revert_to_base()` activa `_revert_zenkai_grace_timer = 6.0s` para no regalar Zenkai al rival tras una destransformación por agotamiento de Ki.
- **Avisos Centrales de Turno (`DramaticDirector.show_center_prompt`):** pre-alocado en `_build_camera_overlays()` dentro de `XRCamera3D` (`Vector3(0.0, 0.02, -1.08)`, `render_priority = 126..127` máximo permitido por Godot), animado en `real_delta` con `set_ignore_time_scale(true)` y arbitrado por prioridad para no superponer nunca avisos de melee, Follow-Up, Súper entrante, Beam Clash ni Remate Zenkai.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
