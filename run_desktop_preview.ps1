param(
    [switch]$Arena,
    [switch]$MeleeHud,
    [switch]$KiAura,
    [string]$Resolution = "1440x820"
)
$godot = "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe"
$project = "d:\Mis Documentos\dbzvr"

if ($Arena) {
    Write-Host "[DBZVR] Abriendo Arena de Combate (Desktop $Resolution)..." -ForegroundColor Cyan
    & $godot --xr-mode off --path $project --resolution $Resolution
} elseif ($MeleeHud) {
    Write-Host "[DBZVR] Abriendo Selector Interactivo de HUD Melee ($Resolution)..." -ForegroundColor Cyan
    & $godot --xr-mode off --path $project --resolution $Resolution "res://melee_hud_preview.tscn"
} elseif ($KiAura) {
    Write-Host "[DBZVR] Abriendo Probador de Transparencia de Aura de Ki ($Resolution)..." -ForegroundColor Cyan
    Write-Host "  Teclas 1-6: Grados de transparencia | V: 1ra/3ra persona | Arrastra mouse: mirar" -ForegroundColor Gray
    & $godot --xr-mode off --path $project --resolution $Resolution "res://ki_aura_preview.tscn"
} else {
    Write-Host "[DBZVR] Abriendo Zenkai Showcase & Calibrador de Huesos ($Resolution)..." -ForegroundColor Green
    Write-Host "  Base actual: assets/animations/zenkai/skeleton_axis_calibration.json" -ForegroundColor Yellow
    Write-Host "  Calibrados : LeftArm / RightArm (Adelante, Abajo, Arriba)" -ForegroundColor Gray
    Write-Host "  Pendientes : LeftForeArm/RightForeArm (Codos), LeftHand/RightHand (Munecas), LeftUpLeg/RightUpLeg + LeftLeg/RightLeg (Piernas)" -ForegroundColor Gray
    & $godot --xr-mode off --path $project --resolution $Resolution "res://zenkai_showcase.tscn"
}
