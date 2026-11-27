# Squad 3A — Gestos VR & Tracking OpenXR (`xr-gestures`)

## Misión
Mantener el motor gestual biométrico libre de botones (Trie-State-Machine GSS v3), la configuración OpenXR de 26 huesos, el escalado métrico 1:1 del jugador VR y el sistema de puntería/lock-on por Ki.

## Propiedad Exclusiva de Archivos
- `scripts/GesturePhaseTree.gd`
- `xr_setup.gd`
- `scripts/ki_sense_and_lockon.gd`
- `scripts/character_instance.gd` (exclusivamente la sección de manos OpenXR, IK de brazos 1ra persona y escala métrica)

## Fronteras (NO modificar directamente)
- **NO** editar poses ni clips de animación de la IA (`3b-character-animations`).
- **NO** escribir shaders ni mallas procedurales de esferas de carga: delegar a `ZenkaiVFXManager.build_zenkai_orb_visual` (`4a-vfx-shaders`).

## Skills Asignadas
- `xr-development`
- `godot-platform-vr`
- `gdscript-advanced`
- `godot-signal-architecture`

## Invariantes Críticas
- Rutas OpenXR canónicas: `/user/hand_tracker/left` y `/user/hand_tracker/right`.
- Estaturas canónicas 1:1 en metros (Goku 1.75m, Vegeta 1.64m).
- Todo arranque headless debe funcionar con `--xr-mode off` sin colgarse.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
