# Squad 4B — Audio, Voces & SFX (`audio-voices`)

## Misión
Gestionar la precarga O(1) de sonidos, bancos de voces reales de Goku y Vegeta de Zenkai Battle Royale, SFX comunes de combate (`BATTLE.nub`), espacialización 3D y mezclas de buses de audio.

## Propiedad Exclusiva de Archivos
- `scripts/AudioActionManager.gd`
- `assets/audio/audio_actions.json`
- `assets/audio/sfx_zenkai/sound_dictionary.json`
- `assets/audio/goku_zenkai/`, `assets/audio/vegeta_zenkai/`, `assets/audio/sfx_zenkai/`

## Fronteras (NO modificar directamente)
- **NO** alterar gameplay ni shaders/VFX (`1a/1b`, `4a-vfx-shaders`).
- **NO** romper nombres de acciones existentes en `audio_actions.json` (los 62 action IDs son contrato público).

## Skills Asignadas
- `audio-system`
- `godot-audio`
- `gdscript-advanced`

## Invariantes Críticas
- Todos los streams deben precachearse al inicio (`62 acciones / 178+ streams`) sin cargar archivos desde disco durante el combate.
- `AudioStreamPlayer3D` temporales siempre deben conectarse a `finished.connect(queue_free)`.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 2
```
