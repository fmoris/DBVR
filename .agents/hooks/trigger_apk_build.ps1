$ErrorActionPreference = "SilentlyContinue"

$ProjectDir = "d:\Mis Documentos\dbzvr"
$BuildScript = "d:\Mis Documentos\dbzvr\build_apk.ps1"
$LockFile = "d:\Mis Documentos\dbzvr\builds\.apk_build.lock"
$IsDryRun = ($env:DBZVR_HOOK_DRY_RUN -eq "1")

try {
    $rawInput = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($rawInput)) {
        $payload = $rawInput | ConvertFrom-Json
        if ($null -ne $payload) {
            $cmdLine = ""
            if ($null -ne $payload.toolCall -and $null -ne $payload.toolCall.args -and $null -ne $payload.toolCall.args.CommandLine) {
                $cmdLine = [string]$payload.toolCall.args.CommandLine
            }

            $toolError = ""
            if ($null -ne $payload.error) {
                $toolError = [string]$payload.error
            }

            $isGitCommit = ($cmdLine -match '(?i)\bgit\b.*\bcommit\b')
            $hasNoError = [string]::IsNullOrWhiteSpace($toolError)

            if ($isGitCommit -and $hasNoError) {
                $hasApkMarker = ($cmdLine -match '(?i)\[apk\]')
                if (-not $hasApkMarker) {
                    $lastCommitMsg = (& git -C $ProjectDir log -1 --pretty=%B 2>$null) -join "`n"
                    if ($lastCommitMsg -match '(?i)\[apk\]') {
                        $hasApkMarker = $true
                    }
                }

                $noActiveLock = (-not (Test-Path $LockFile))

                if ($hasApkMarker -and $noActiveLock) {
                    if ($IsDryRun) {
                        [Console]::Error.WriteLine("[DBZVR_HOOK_DRY_RUN] Se dispararia build_apk.ps1 en ventana independiente.")
                    } elseif (Test-Path $BuildScript) {
                        Start-Process powershell.exe -ArgumentList @(
                            "-NoExit",
                            "-ExecutionPolicy", "Bypass",
                            "-File", $BuildScript
                        )
                    }
                }
            }
        }
    }
}
catch {
    if ($IsDryRun) {
        [Console]::Error.WriteLine("[DBZVR_HOOK_DRY_RUN] Error procesando payload: $($_.Exception.Message)")
    }
}

[Console]::Out.WriteLine("{}")
exit 0
