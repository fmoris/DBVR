# Squad 1A — Secuencias Melee & Cúpula (`melee-squad`)

## Misión
Implementar y mantener el combate cuerpo a cuerpo en tiempo real, la Cúpula Melee, bloqueos predictivos, desvíos físicos con manos, seguimiento aéreo (Meteor Chase / Meteor Smash) y eventos dramáticos melee.

## Propiedad Exclusiva de Archivos
- `scripts/MeleeTargetDome.gd`
- `scripts/FollowUpSequenceController.gd`
- `scripts/MeleeLoreEventController.gd`
- `scripts/HybridCombatController.gd` (sección melee, dash, guardia cruzada, desvío físico y Momento de Determinación)

## Fronteras (NO modificar directamente)
- **NO** crear shaders ni partículas ad-hoc: solicitar VFX a `4a-vfx-shaders` vía `ZenkaiVFXManager` / `KiSmokeFX`.
- **NO** modificar fórmulas de NP/Ki/Furia: usar los métodos públicos de `CharacterInstance` (propiedad de `2-ki-bp-systems`).
- **NO** editar lógica de `SuperBeamSequenceController.gd` ni `BeamClashController.gd` (propiedad de `1b-super-beams`).

## Skills Asignadas
- `godot-genre-fighting`
- `godot-combat-system`
- `state-machine`
- `physics-system`
- `godot-signal-architecture`

## Invariantes Críticas
- Toda cadena melee debe garantizar salida limpia (sin dejar al jugador o IA congelados en Bullet-Time o Cúpula; `Engine.time_scale = 1.0` en `_exit_tree` y `_finish_sequence`).
- Cero alocaciones en `_process` / `_physics_process`.
- Toda física multiplicada por `delta`.
- En Bullet-Time (`Engine.time_scale = 0.12` durante Follow-Up), todo temporizador de input/carga/pose/aire (`FollowUpSequenceController`, pose/carga de Súper y Air Brake en `HybridCombatController`) **debe usar `real_dt = clampf(delta / maxf(Engine.time_scale, 0.005), 0.001, 0.08)`**; nunca acumular `delta` escalado para poses ni gatillos.
- En `FollowUpSequenceController.choose_melee_chase()`, invocar `attacker.start_flight_to_opponent()` **antes** de `_finish_sequence("melee_chase", false)` para que `was_followup_chase` sea `true` (preservando Z-Blink aéreo, `2.2×` velocidad, `pending_followup_bonus_hits` y sin duplicar `combat_chain_depth`).
- `complete_air_brake()` habilita defensa pasando al defensor a `STABILIZED`, pero **nunca** cancela el `FollowUpSequenceController` activo del atacante.
- `_exit_tree()` en `MeleeTargetDome.gd` y `FollowUpSequenceController.gd` **nunca** debe reiniciar `Engine.time_scale = 1.0` a ciegas si otro controlador activo (`active_followup_controller`, `active_target_dome`, `is_in_bullet_time`, `is_in_beam_sequence`, `is_in_beam_clash`) posee el Bullet-Time; además todo tween de cierre/encogimiento debe usar `tw.set_ignore_time_scale(true)`.
- `_is_followup_minigame_locked(player)` en `HybridCombatController.gd` debe revisar tanto `player` como `opp`, y `_process_grid_step_movement()` debe bloquear pasos discretos durante `is_in_bullet_time`, `is_in_beam_sequence`, `is_in_beam_clash` y minijuegos Follow-Up para que el flick de `Stick` de Z-Vanish nunca dispare un tween lateral que arrastre `XROrigin3D`.
- `start_flight_to_opponent()` limpia `pending_followup_bonus_hits = 0`; cualquier contraataque con Z-Dash (`start_counter_melee_reversal`) debe aplicar bonos y `_dash_speed_mult` **después** de llamarla.
- `HybridCombatController` proyecta la extensión de brazos sobre `cam_fwd_3d` (`l_cam_fwd_3d_proj` / `r_cam_fwd_3d_proj`) y amplía el rango vertical `hand_torso.y` (`[-0.68, 0.72]`) cuando `absf(cam_fwd_3d.y) >= 0.25` para permitir Ki Blasts y Súper Poderes apuntando en picada o hacia arriba sin falsos positivos con Recarga de Ki; además `FollowUpSequenceController._execute_hammer_slam_impact()` estampa al rival en diagonal adelante (`diag_dist = clampf(drop_h * 1.55, 5.5, 13.5)`, nunca vertical debajo de los pies y sin rotar `XRCamera3D`).
- En `MeleeTargetDome.gd`, el feedback visual tras cada nota/zona resuelta (`_morph_zone_to_outcome_icon`) reutiliza `inner_mesh` (fondo Zenkai `alert_base_{g,y,b,r}.png`) + `outcome_icon_mesh` (`OutcomeIconQuad`, malla compartida y pre-alocada en `_build_target_boxes()`, con texturas SDF en caché `_outcome_icon_cache`), ocultando `box_mesh`/`circle_mesh`/`circle_ring` y animando con `set_ignore_time_scale(true)` sin bloquear nunca una nueva nota entrante en el mismo `zone_id` (`_update_defense_zone_highlights` y `_sync_simultaneous_zone_visuals` limpian el outcome previo si esa zona pasa a ser activa).
- Al iniciar ataque melee del jugador (`start_attack_phase`), `attack_intro_pause_timer = 0.45s` congela el avance de `time_left` y los gestos de golpe en `_process_attack_recording()` mientras se muestra `DramaticDirector.show_center_prompt("¡TE TOCA ATACAR!", ...)`; cada transición de `MeleeTargetDome` (`start_defense`, `restart_attacker`, `continue_offense`, `start_simultaneous`, `_start_unblockable_ki_break`) y cada intervalo de `FollowUpSequenceController` (`_enter_intro_pause`, `choose_vanish_hammer`, `choose_ki_barrage`) dispara su aviso central correspondiente.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
