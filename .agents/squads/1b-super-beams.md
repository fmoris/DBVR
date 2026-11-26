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
- `_exit_tree()` en `SuperBeamSequenceController.gd` y `BeamClashController.gd` debe verificar `_has_other_active_bullet_time()` antes de restaurar `Engine.time_scale = 1.0`, y los tweens de cierre deben llevar `tw.set_ignore_time_scale(true)` para no bloquear ni pisar una secuencia Follow-Up (`0.005×`) o Cúpula Melee de contraataque recién abierta.
- Limpiar siempre `attacker.active_beam_sequence = null` en `_cleanup_and_finish` y `_exit_tree()`, y al leer `active_beam_sequence` desde `character_instance.gd` usar `Variant` + `is_instance_valid(...)` antes de castear a `Node` (evita `Trying to assign invalid previously freed instance` en GDScript 4).

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
