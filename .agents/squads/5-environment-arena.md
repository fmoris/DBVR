# Squad 5 — Entorno, Arena & Destrucción (`environment-arena`)

## Misión
Construir, mantener y optimizar la Arena de los Juegos de Cell (cuadrilátero de piedra 32×32m, 4 pilares angulares, llanura exterior, cordillera 360°, iluminación de entorno) y su sistema de destrucción física/visual.

## Propiedad Exclusiva de Archivos
- `cell_games_arena.tscn`
- `build_arena.gd`
- `scripts/ArenaDestructionManager.gd`

## Fronteras (NO modificar directamente)
- **NO** tocar lógica de combate ni recursos de personajes (`1a/1b`, `2-ki-bp-systems`, `6-lore-balance`).
- **NO** reemplazar humo/cráteres por mallas procedurales: usar `KiSmokeFX` y `ZenkaiVFXManager` (`4a-vfx-shaders`).

## Skills Asignadas
- `3d-essentials`
- `rendering-pipeline`
- `physics-system`
- `godot-performance-optimization`
- `scene-organization`

## Invariantes Críticas
- `RING_HALF_SIZE = 16.0` (suelo del ring en `Y = 0.5`, llanura exterior en `Y = 0.0`).
- Presupuesto GPU móvil estricto para sostener 90 FPS en Meta Quest 3 (evitar luces con sombras dinámicas extras).

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
