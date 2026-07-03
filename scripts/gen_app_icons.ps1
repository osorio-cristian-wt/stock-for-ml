# Genera los íconos de la app (Android legacy + adaptive, iOS) desde el
# isotipo del Manual de Marca (docs/brand/app-icon.svg es la fuente vectorial).
# Redibuja el vector con GDI+ a cada tamaño (con supersampling 4x) para no
# depender de herramientas externas de rasterizado.
#
# Uso:  powershell -File scripts/gen_app_icons.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repo    = Split-Path -Parent $PSScriptRoot
$android = Join-Path $repo 'apps\mobile\android\app\src\main\res'
$ios     = Join-Path $repo 'apps\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset'

$emerald = [System.Drawing.Color]::FromArgb(255, 0x10, 0xB9, 0x81)
$emerald50 = [System.Drawing.Color]::FromArgb(128, 0x10, 0xB9, 0x81)
$carbon  = [System.Drawing.Color]::FromArgb(255, 0x0D, 0x0F, 0x13)

# Dibuja el isotipo (viewBox 0..64 del manual) centrado en un canvas de $size
# px, ocupando $iconFrac del lado. $opaque pinta el fondo Carbón.
function New-IconBitmap([int]$size, [double]$iconFrac, [bool]$opaque) {
  $ss = 4  # supersampling
  $big = $size * $ss
  $bmp = New-Object System.Drawing.Bitmap($big, $big)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  if ($opaque) { $g.Clear($carbon) } else { $g.Clear([System.Drawing.Color]::Transparent) }

  $d = $big * $iconFrac          # lado del viewBox 64 en px
  $s = $d / 64.0                 # escala unidad-viewBox → px
  $off = ($big - $d) / 2.0
  function P([double]$x, [double]$y) {
    New-Object System.Drawing.PointF(($off + $x * $s), ($off + $y * $s))
  }

  $pen = New-Object System.Drawing.Pen($emerald, (3.2 * $s))
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round

  # Hexágono cerrado.
  $hex = [System.Drawing.PointF[]]@((P 32 6), (P 56 18), (P 56 46), (P 32 58), (P 8 46), (P 8 18))
  $g.DrawPolygon($pen, $hex)
  # V superior.
  $g.DrawLines($pen, [System.Drawing.PointF[]]@((P 8 18), (P 32 30), (P 56 18)))
  # Vertical central.
  $g.DrawLine($pen, (P 32 30), (P 32 58))
  # Diagonal al 50%.
  $pen50 = New-Object System.Drawing.Pen($emerald50, (3.2 * $s))
  $pen50.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen50.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawLine($pen50, (P 20 12), (P 44 24))

  $g.Dispose(); $pen.Dispose(); $pen50.Dispose()

  # Downsample al tamaño final.
  $final = New-Object System.Drawing.Bitmap($size, $size)
  $gf = [System.Drawing.Graphics]::FromImage($final)
  $gf.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gf.DrawImage($bmp, 0, 0, $size, $size)
  $gf.Dispose(); $bmp.Dispose()
  return $final
}

function Save-Icon([int]$size, [double]$frac, [bool]$opaque, [string]$path) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  $bmp = New-IconBitmap $size $frac $opaque
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "  $path"
}

Write-Host 'Android (legacy full-bleed):'
$densities = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $densities.GetEnumerator()) {
  Save-Icon $d.Value 0.66 $true (Join-Path $android "mipmap-$($d.Key)\ic_launcher.png")
}

Write-Host 'Android (adaptive foreground, safe zone 66/108):'
$fg = @{ 'mdpi' = 108; 'hdpi' = 162; 'xhdpi' = 216; 'xxhdpi' = 324; 'xxxhdpi' = 432 }
foreach ($d in $fg.GetEnumerator()) {
  Save-Icon $d.Value 0.40 $false (Join-Path $android "mipmap-$($d.Key)\ic_launcher_foreground.png")
}

Write-Host 'iOS (opacos, esquinas las pone el sistema):'
$iosIcons = @(
  @('Icon-App-20x20@1x.png', 20), @('Icon-App-20x20@2x.png', 40), @('Icon-App-20x20@3x.png', 60),
  @('Icon-App-29x29@1x.png', 29), @('Icon-App-29x29@2x.png', 58), @('Icon-App-29x29@3x.png', 87),
  @('Icon-App-40x40@1x.png', 40), @('Icon-App-40x40@2x.png', 80), @('Icon-App-40x40@3x.png', 120),
  @('Icon-App-60x60@2x.png', 120), @('Icon-App-60x60@3x.png', 180),
  @('Icon-App-76x76@1x.png', 76), @('Icon-App-76x76@2x.png', 152),
  @('Icon-App-83.5x83.5@2x.png', 167),
  @('Icon-App-1024x1024@1x.png', 1024)
)
foreach ($i in $iosIcons) {
  Save-Icon $i[1] 0.66 $true (Join-Path $ios $i[0])
}

Write-Host 'Listo.'
