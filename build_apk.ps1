param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ProjectDir = "d:\Mis Documentos\dbzvr"
$GodotCli   = "D:\Download\Godot_v4.8-beta2_win64.exe\Godot_v4.8-beta2_win64_console.exe"
$ApkPath    = "d:\Mis Documentos\dbzvr\builds\dbzvr.apk"
$BuildsDir  = "d:\Mis Documentos\dbzvr\builds"
$LockFile   = "d:\Mis Documentos\dbzvr\builds\.apk_build.lock"
$GradleBat  = "d:\Mis Documentos\dbzvr\android\build\gradlew.bat"
$AdbExe     = "D:\androidSdk\platform-tools\adb.exe"
$ProjectFile = Join-Path $ProjectDir "project.godot"

$startTime = Get-Date
$lockCreated = $false
$runGradleStop = $false

try {
    if (-not (Test-Path $BuildsDir)) {
        Write-Host "[ERROR] No existe la carpeta builds\: $BuildsDir" -ForegroundColor Red
        exit 1
    }

    if (Test-Path $LockFile) {
        $lockInfo = Get-Content -Path $LockFile -Raw -ErrorAction SilentlyContinue
        Write-Host "[WARN] Ya existe un build en curso ($LockFile). Contenido: $lockInfo" -ForegroundColor Yellow
        exit 1
    }

    $lockPayload = "PID=$PID; Started=$($startTime.ToString('yyyy-MM-dd HH:mm:ss')); DryRun=$DryRun"
    Set-Content -Path $LockFile -Value $lockPayload -Encoding UTF8
    $lockCreated = $true

    $gitBranch = (& git -C $ProjectDir rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitBranch)) { $gitBranch = "(desconocida)" }
    $gitCommit = (& git -C $ProjectDir log -1 --oneline 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommit)) { $gitCommit = "(sin commits)" }

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  DBZVR — Build APK Fuera del Chat (0 Tokens)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Inicio : $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  Rama   : $gitBranch"
    Write-Host "  Commit : $gitCommit"
    if ($DryRun) {
        Write-Host "  Modo   : DRY-RUN (validacion sin compilar)" -ForegroundColor Yellow
    }
    Write-Host "============================================================" -ForegroundColor Cyan

    $requiredPaths = @(
        @{ Name = "Godot CLI";      Path = $GodotCli },
        @{ Name = "project.godot";  Path = $ProjectFile },
        @{ Name = "Carpeta builds"; Path = $BuildsDir },
        @{ Name = "Gradle wrapper"; Path = $GradleBat },
        @{ Name = "ADB";            Path = $AdbExe }
    )

    foreach ($item in $requiredPaths) {
        if (-not (Test-Path $item.Path)) {
            Write-Host "[ERROR] No se encontro $($item.Name): $($item.Path)" -ForegroundColor Red
            exit 1
        }
    }

    $godotArgs = @(
        "--headless",
        "--xr-mode", "off",
        "--path", "`"$ProjectDir`"",
        "--export-debug", "`"Android`"",
        "`"$ApkPath`""
    )

    if ($DryRun) {
        Write-Host "[DRY-RUN] Todas las rutas verificadas correctamente." -ForegroundColor Green
        Write-Host "[DRY-RUN] Comando exacto:" -ForegroundColor Green
        Write-Host "  `"$GodotCli`" $($godotArgs -join ' ')" -ForegroundColor Gray
        exit 0
    }

    Write-Host "[INFO] Iniciando export Android Debug..." -ForegroundColor Yellow
    $runGradleStop = $true
    $proc = Start-Process -FilePath $GodotCli -ArgumentList $godotArgs -Wait -NoNewWindow -PassThru
    $exitCode = $proc.ExitCode

    if ($exitCode -ne 0) {
        [console]::beep(400, 500)
        Write-Host "[ERROR] La compilacion fallo con ExitCode=$exitCode." -ForegroundColor Red
        exit $exitCode
    }

    if (-not (Test-Path $ApkPath)) {
        [console]::beep(400, 500)
        Write-Host "[ERROR] Godot termino con 0 pero no se encontro el APK en $ApkPath" -ForegroundColor Red
        exit 1
    }

    $endTime = Get-Date
    $elapsed = $endTime - $startTime
    $apkInfo = Get-Item $ApkPath
    $sizeMb = [math]::Round($apkInfo.Length / 1MB, 2)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  APK COMPILADO CON EXITO" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  Archivo   : $ApkPath"
    Write-Host "  Tamano    : $sizeMb MB"
    Write-Host "  Fecha     : $($apkInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "  Duracion  : $([int]$elapsed.TotalMinutes)m $($elapsed.Seconds)s"
    Write-Host "============================================================" -ForegroundColor Green

    [console]::beep(880, 200)
    [console]::beep(1175, 250)

    Write-Host ""
    Write-Host "[INFO] Verificando dispositivos ADB conectados..." -ForegroundColor Cyan
    $adbOutput = & $AdbExe devices 2>&1
    $adbOutput | ForEach-Object { Write-Host "  $_" }

    $connectedDevices = @($adbOutput | Where-Object { $_ -match '^\S+\s+device$' })
    if ($connectedDevices.Count -eq 0) {
        Write-Host ""
        Write-Host "[INFO] No hay ningun Meta Quest conectado en estado 'device'." -ForegroundColor Yellow
        Write-Host "[INFO] El APK quedo compilado y listo en: $ApkPath" -ForegroundColor Green
        Write-Host ""
        if ($Host.Name -eq "ConsoleHost") {
            Write-Host "Presiona cualquier tecla para cerrar..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        exit 0
    }

    Write-Host ""
    $answer = Read-Host "¿Instalar ahora en Meta Quest 3? [S/N]"
    if ($answer -match '^[Ss]$') {
        Write-Host "[INFO] Instalando APK en Meta Quest 3..." -ForegroundColor Cyan
        & $AdbExe install -r $ApkPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] APK instalado correctamente en Meta Quest 3." -ForegroundColor Green
        } else {
            [console]::beep(400, 500)
            Write-Host "[ERROR] adb install fallo con codigo $LASTEXITCODE." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    } else {
        Write-Host "[INFO] Instalacion omitida por el usuario. APK listo en: $ApkPath" -ForegroundColor Yellow
    }

    exit 0
}
finally {
    if ($runGradleStop -and (Test-Path $GradleBat)) {
        Write-Host "[INFO] Deteniendo Gradle daemon..." -ForegroundColor DarkGray
        & $GradleBat --stop 2>&1 | Out-Null
    }
    if ($lockCreated -and (Test-Path $LockFile)) {
        Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
    }
}
