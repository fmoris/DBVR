# Squad 4A — VFX, Shaders & Partículas (`vfx-shaders`)

## Misión
Diseñar, optimizar y mantener todos los efectos visuales 100% Zenkai Battle Royale (auras, bio-rayos 4×4, orbes de Ki, Super Beams, explosiones 4×4, humo anime 4×4, impactos, cráteres e iluminación dinámica) a 90 FPS estables en Meta Quest 3.

## Propiedad Exclusiva de Archivos
- `scripts/ZenkaiVFXManager.gd`
- `scripts/KiSmokeFX.gd`
- `shaders/*.gdshader`
- `assets/vfx_zenkai/`
- `scripts/character_instance.gd` (exclusivamente `_update_aura_visuals`)

## Fronteras (NO modificar directamente)
- **NO** modificar lógica de daño, Ki/NP ni audio (`2-ki-bp-systems`, `4b-audio-voices`).
- **PROHIBIDO** reintroducir shaders viejos (`ki_sphere.gdshader`, `ki_corona.gdshader`) ni esferas procedurales de chispas.

## Skills Asignadas
- `godot-shader-vfx-library`
- `shader-basics`
- `godot-shaders-vfx`
- `particles-vfx`
- `rendering-pipeline`
- `godot-polish`

## Invariantes Críticas
- Toda textura en `assets/vfx_zenkai/particles/` debe cargarse a través del caché estático `ZenkaiVFXManager.get_tex(key)` (zero-allocation).
- `OmniLight3D` dinámicos siempre con `shadow_enabled = false` y bajo pool acotado.
- Validar visualmente todo cambio de VFX en `zenkai_showcase.tscn` antes de compilar APK.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" "res://zenkai_showcase.tscn" --quit-after 2
```
