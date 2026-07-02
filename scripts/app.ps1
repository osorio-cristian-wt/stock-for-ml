# Corre o compila la app Flutter eligiendo entorno (local/prod) y modo.
# Los entornos son archivos apps/mobile/.env.<entorno> (ver .env.example)
# inyectados via --dart-define-from-file.
#
# Uso:
#   .\scripts\app.ps1                                  # run · local · debug
#   .\scripts\app.ps1 -Entorno prod                    # run · cloud · debug
#   .\scripts\app.ps1 -Entorno prod -Accion apk        # APK release contra cloud
#   .\scripts\app.ps1 -Accion apk -Modo debug          # APK debug contra local
#   .\scripts\app.ps1 -Entorno prod -Accion appbundle  # AAB release (Play Store)
#   .\scripts\app.ps1 -Dispositivo emulator-5554       # elegir device de `flutter devices`
#   .\scripts\app.ps1 -Entorno prod -SoloComando       # imprime el comando sin ejecutar

param(
    [ValidateSet('local', 'prod')]
    [string]$Entorno = 'local',

    [ValidateSet('run', 'apk', 'appbundle')]
    [string]$Accion = 'run',

    # Default: debug para `run`, release para builds.
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Modo,

    [string]$Dispositivo,

    [switch]$SoloComando
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $repoRoot 'apps\mobile'
$envFile = Join-Path $appDir ".env.$Entorno"

if (-not (Test-Path $envFile)) {
    throw "No existe $envFile. Copiá apps/mobile/.env.example a .env.$Entorno y completalo."
}

if (-not $Modo) {
    if ($Accion -eq 'run') { $Modo = 'debug' } else { $Modo = 'release' }
}

$flutterArgs = @()
switch ($Accion) {
    'run'       { $flutterArgs += 'run' }
    'apk'       { $flutterArgs += 'build', 'apk' }
    'appbundle' { $flutterArgs += 'build', 'appbundle' }
}

# `flutter run` es debug por defecto; los builds piden el modo explícito.
if ($Accion -eq 'run') {
    if ($Modo -ne 'debug') { $flutterArgs += "--$Modo" }
} else {
    $flutterArgs += "--$Modo"
}

$flutterArgs += "--dart-define-from-file=$envFile"
if ($Dispositivo) { $flutterArgs += '-d', $Dispositivo }

Write-Host "[$Entorno] flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
if ($Entorno -eq 'prod') {
    Write-Host 'Recordá: el cloud necesita migraciones/functions/secrets deployados (docs/guia-tecnica-ml-app.md §3).' -ForegroundColor Yellow
}
if ($SoloComando) { return }

Push-Location $appDir
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter terminó con código $LASTEXITCODE" }
} finally {
    Pop-Location
}
