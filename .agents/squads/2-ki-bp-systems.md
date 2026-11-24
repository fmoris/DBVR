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

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
