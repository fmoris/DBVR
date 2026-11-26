# Squad 7 — QA, Preview Escritorio & Release APK (`qa-release-ops`)

## Misión
Operar las herramientas de validación rápida en escritorio (sin APK), pruebas automatizadas headless, auditoría de memoria/fugas, mantenimiento de `FEATURE_MAP.md`, Git-Flow y compilación controlada de `builds/dbzvr.apk`.

## Propiedad Exclusiva de Archivos
- `zenkai_showcase.tscn`
- `scripts/ZenkaiShowcaseViewer.gd`
- `run_desktop_preview.ps1`
- `build_apk.ps1`
- `build_apk.bat`
- `.agents/hooks.json`
- `.agents/hooks/trigger_apk_build.ps1`
- `scripts/tests/CombatSequenceRunner.gd`
- `FEATURE_MAP.md`

## Fronteras (NO modificar directamente)
- **NO** parchear lógica de combate directamente sin coordinar con el squad dueño (`1a`–`6`).
- **NUNCA** desplegar ni instalar `builds/dbzvr.apk` en Meta Quest 3 por ADB sin autorización explícita del usuario.

## Skills Asignadas
- `godot-headless-workflow`
- `godot-auditor`
- `godot-code-review`
- `godot-debugging`
- `godot-performance`
- `mobile-development`
- `export-pipeline`

## Invariantes Críticas
- Todo cambio visual/animación/UI se valida primero en escritorio con `run_desktop_preview.ps1` antes de compilar APK.
- Todo export de APK debe detener el Gradle daemon (`gradlew.bat --stop`) al terminar.
- Verificar `adb devices` antes de instalar cuando el usuario autorice el envío.

## Gate de Verificación
```powershell
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" --quit-after 3
& "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe" --headless --xr-mode off --path "d:\Mis Documentos\dbzvr" "res://zenkai_showcase.tscn" --quit-after 2
```
