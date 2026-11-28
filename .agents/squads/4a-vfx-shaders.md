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
- Aura Ki de ambos peleadores (jugador y contrincante) calibrada con `DEFAULT_AURA_OPACITY_MULT = 0.24`, `DEFAULT_AURA_FLAME_ALPHA_MULT = 0.11` y `DEFAULT_AURA_LIGHTNING_ALPHA_MULT = 0.43`; `aura_fp_center_clear = 1.00` solo para el jugador en 1ra persona VR (`0.0` para el rival), sin `AuraGroundRing` en el piso.
- Texturas de aura Zenkai (`aura_vertical_streaks.png`, `aura_flame_band.png`, `aura_v_flame_white.png`, `aura_radial_spikes.png`) tienen `RGB=255` uniforme y codifican la máscara en el canal Alpha: los shaders deben muestrear `tex.r * tex.a` (nunca `.r` solo).

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" "res://zenkai_showcase.tscn" --quit-after 2
```
