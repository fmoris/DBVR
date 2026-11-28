# Squad 6 — Lore, Personajes & Balance Canon (`lore-balance`)

## Misión
Garantizar la fidelidad canónica de Dragon Ball Z y del GDD de DBVR en perfiles de personajes (Goku y Vegeta), transformaciones, herencia de técnicas, costos de Ki, multiplicadores de NP, estaturas 1:1 y textos/banners de combate.

## Propiedad Exclusiva de Archivos
- `resources/goku.tres`
- `resources/goku_zenkai.tres`
- `resources/vegeta.tres`
- `resources/vegeta_zenkai.tres`
- `scripts/resources/character_data.gd`
- `scripts/resources/power_data.gd`
- `scripts/resources/transformation_data.gd`

## Fronteras (NO modificar directamente)
- **NO** hardcodear datos de personajes en scripts de gameplay (`character_instance.gd`, `CombatAIController.gd`): todo parámetro numérico o de perfil vive en `.tres` (Data-Driven).

## Skills Asignadas
- `resource-pattern`
- `godot-resource-data-patterns`
- `godot-director`
- `godot-distiller`

## Invariantes Críticas
- Goku: NP Base 9.000, estatura 1.75m; Genkidama prohibida en SSJ.
- Vegeta: NP Base 10.000, estatura 1.64m.
- Toda técnica desbloqueada en una transformación previa se hereda en formas posteriores.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
```
