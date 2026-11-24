# Squad 1B — Súper Ataques, Proyectiles & Beam Clash (`super-beam-squad`)

## Misión
Gestionar proyectiles de Ki (rápidos y cargados), secuencias Bullet-Time de Súper Ataques (Kamehameha, Galick Ho, Final Flash, Big Bang, Genkidama), ventanas de reacción (Z-Vanish, desvío, contención) y choques de poderes (Beam Clash).

## Propiedad Exclusiva de Archivos
- `scripts/SuperBeamSequenceController.gd`
- `scripts/BeamClashController.gd`
- `scripts/ProceduralKiProjectile.gd`

## Fronteras (NO modificar directamente)
- **NO** crear mallas procedurales de esferas/chispas/cráteres: consumir exclusivamente las fábricas de `ZenkaiVFXManager` y `KiSmokeFX` (`4a-vfx-shaders`).
- **NO** tocar reconocimiento de gestos en `GesturePhaseTree.gd` (`3a-xr-gestures`).
- **NO** alterar umbrales de NP/Zenkai en `character_instance.gd` (`2-ki-bp-systems`).

## Skills Asignadas
- `godot-combat-system`
- `godot-signal-architecture`
- `tween-animation`
- `physics-system`
- `godot-raycasting-queries`

## Invariantes Críticas
- El Bullet-Time adaptativo siempre debe restaurar `Engine.time_scale = 1.0` al finalizar o cancelar la secuencia.
- En Beam Clash, la IA no dispara Ki Blasts durante el choque; el haz avanza y resuelve al llegar a 0 Ki o desistir.
- Cero referencias a `ki_sphere.gdshader` o `ki_corona.gdshader`.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
