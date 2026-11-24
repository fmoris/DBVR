# Squad 1A — Secuencias Melee & Cúpula (`melee-squad`)

## Misión
Implementar y mantener el combate cuerpo a cuerpo en tiempo real, la Cúpula Melee, bloqueos predictivos, desvíos físicos con manos, seguimiento aéreo (Meteor Chase / Meteor Smash) y eventos dramáticos melee.

## Propiedad Exclusiva de Archivos
- `scripts/MeleeTargetDome.gd`
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
- Toda cadena melee debe garantizar salida limpia (sin dejar al jugador o IA congelados en Bullet-Time o Cúpula).
- Cero alocaciones en `_process` / `_physics_process`.
- Toda física multiplicada por `delta`.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
