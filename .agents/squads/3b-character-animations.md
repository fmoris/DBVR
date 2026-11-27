# Squad 3B — Movimientos, Rigging & Animaciones (`character-animations`)

## Misión
Controlar el esqueleto de 18 huesos, poses de combate, transiciones suaves (`slerp`), ragdoll físico en runtime y calibración de ejes de modelos GLB de Goku y Vegeta.

## Propiedad Exclusiva de Archivos
- `scripts/ProceduralCombatAnimator.gd`
- `scripts/ZenkaiAnimationLoader.gd`
- `scripts/runtime_ragdoll_generator.gd`
- `assets/animations/zenkai/skeleton_axis_calibration.json`
- `assets/animations/zenkai/*.json`

## Fronteras (NO modificar directamente)
- **NO** tocar detección de gestos VR (`3a-xr-gestures`) ni decisiones de IA (`2-ki-bp-systems`).
- **NO** activar modos experimentales sin validar visualmente primero en escritorio con `run_desktop_preview.ps1`.

## Skills Asignadas
- `animation-system`
- `godot-animation`
- `godot-physics-3d`
- `godot-gdscript-mastery`

## Invariantes Críticas
- Respetar el mapa empírico de ejes en `skeleton_axis_calibration.json` (`21_goku1_body.glb`).
- Cero alocaciones por frame en `ProceduralCombatAnimator.update()`.
- Validar siempre visualmente en `zenkai_showcase.tscn` antes de compilar APK.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --check-only --script "res://scripts/ProceduralCombatAnimator.gd"
& "d:\Mis Documentos\dbzvr\run_desktop_preview.ps1"
```
