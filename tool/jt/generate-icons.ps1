<#
.SYNOPSIS
  Genereert alle JT-Streaming-iconen reproduceerbaar uit de bronlogo's.

.DESCRIPTION
  Bron: assets/jt/source/ (kopieën van de board-logo's, SHA-256 gecontroleerd).
  Uitvoer:
    - assets/jt/icon.png                       (512x512, in-app icoon)
    - web/icons/Icon-*.png                     (icons_launcher, volledig logo)
    - assets/jt/source/Favicon_JT-Streaming-monogram.png (512x512, getekend JT-monogram)
    - web/favicon.png                          (32x32, monogram)
    - web/favicon.ico, windows/runner/resources/app_icon.ico
                                               (16/32 monogram, 48/64/256 volledig logo)
    - assets/jt/login_background.jpg           (1600 px breed, achtergrond aanmeldpagina)
  Idempotent: bestanden worden alleen herschreven als de inhoud verandert.

.PARAMETER SourceDir
  Optioneel: map met nieuwe Logo_JT-Streaming.png/Favicon_JT-Streaming.png. Ze worden naar
  assets/jt/source/ gekopieerd. Pas daarna de verwachte hashes hieronder aan.
#>
[CmdletBinding()]
param(
  [string]$SourceDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutterRoot = if ($env:JT_FLUTTER_ROOT) { $env:JT_FLUTTER_ROOT } else { 'C:\paperclip\tools\flutter-3.35.7\flutter' }
$dart = Join-Path $flutterRoot 'bin\dart.bat'
if (-not (Test-Path $dart)) { throw "Dart niet gevonden: $dart (zet `$env:JT_FLUTTER_ROOT)" }

# Verwachte SHA-256 van de bronlogo's (zie assets/logo/README.md in de projectmap).
$expected = [ordered]@{
  'Favicon_JT-Streaming.png' = 'EC0BB731331D56C0579F67A5249C9D4DBB1FB83EE46A4B26D3BFD12C4C8A0C90'
  'Logo_JT-Streaming.png'    = '32664B992FF1BF7A596CD9CE22F0632A02D496E75C315DD3C76AA539140AE524'
}

$srcDir = Join-Path $repo 'assets\jt\source'
if ($SourceDir) {
  foreach ($name in $expected.Keys) {
    Copy-Item -LiteralPath (Join-Path $SourceDir $name) -Destination (Join-Path $srcDir $name) -Force
  }
}
foreach ($name in $expected.Keys) {
  $file = Join-Path $srcDir $name
  if (-not (Test-Path $file)) { throw "Bronlogo ontbreekt: $file" }
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash
  if ($hash -ne $expected[$name]) { throw "SHA-256 van $name klopt niet: $hash (verwacht $($expected[$name]))" }
}
Write-Host "Bronlogo's OK (SHA-256)."

function Write-IfChanged([string]$tmp, [string]$target) {
  if ((Test-Path $target) -and ((Get-FileHash $tmp).Hash -eq (Get-FileHash $target).Hash)) {
    Remove-Item $tmp
    return $false
  }
  Move-Item -Force $tmp $target
  return $true
}

# 1. In-app icoon (512x512) uit het transparante favicon.
Add-Type -AssemblyName System.Drawing
$iconTarget = Join-Path $repo 'assets\jt\icon.png'
$iconTmp = "$iconTarget.tmp"
$src = [System.Drawing.Image]::FromFile((Join-Path $srcDir 'Favicon_JT-Streaming.png'))
try {
  $bmp = [System.Drawing.Bitmap]::new(512, 512, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $g.Clear([System.Drawing.Color]::Transparent)
      $g.DrawImage($src, 0, 0, 512, 512)
    } finally { $g.Dispose() }
    $bmp.Save($iconTmp, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $bmp.Dispose() }
} finally { $src.Dispose() }
if (Write-IfChanged $iconTmp $iconTarget) { Write-Host 'assets/jt/icon.png bijgewerkt.' } else { Write-Host 'assets/jt/icon.png ongewijzigd.' }

# 2. Web- en Windows-iconen met icons_launcher (zelfde tool als upstream).
Push-Location $repo
try {
  & $dart run icons_launcher:create --path tool/jt/icons_launcher-jt.yaml
  if ($LASTEXITCODE -ne 0) { throw "icons_launcher faalde (exit $LASTEXITCODE)" }
} finally { Pop-Location }

# 3. Kleine formaten (16/32 px) = alleen het JT-monogram; het volledige logo is daar onleesbaar.
#    Het monogram is getekend (vlakke letters in de logokleuren), niet uitgesneden: een uitsnede
#    van de foto-textuur in de letters is op 32 px al een vlek. Vorm aanpassen = punten hieronder.
$monoBackground = [System.Drawing.Color]::FromArgb(255, 11, 11, 13)    # #0B0B0D, zwart van het logo
$monoBorder     = [System.Drawing.Color]::FromArgb(255, 216, 143, 72)  # #D88F48 = JtTheme.accent
$monoLetterTop  = [System.Drawing.Color]::FromArgb(255, 255, 196, 120) # verloop boven
$monoLetterLow  = [System.Drawing.Color]::FromArgb(255, 216, 143, 72)  # verloop onder

function New-Point([float]$x, [float]$y) { [System.Drawing.PointF]::new($x, $y) }

function Set-Quality([System.Drawing.Graphics]$g) {
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
}

# Monogram op een raster van 100x100: afgeronde zwarte tegel, oranje rand, schuine J en T.
function New-Monogram([int]$size) {
  $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    Set-Quality $g
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform($size / 100.0, $size / 100.0)
    $tile = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $r = 18; $i = 2.5; $e = 100 - $i
    $tile.AddArc($i, $i, 2 * $r, 2 * $r, 180, 90)
    $tile.AddArc($e - 2 * $r, $i, 2 * $r, 2 * $r, 270, 90)
    $tile.AddArc($e - 2 * $r, $e - 2 * $r, 2 * $r, 2 * $r, 0, 90)
    $tile.AddArc($i, $e - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $tile.CloseFigure()
    $g.FillPath([System.Drawing.SolidBrush]::new($monoBackground), $tile)
    $g.DrawPath([System.Drawing.Pen]::new($monoBorder, 5), $tile)

    # Letters: rond (51,51) geschaald naar 74 % en 0.14 schuin (cursief zoals het logo).
    $g.TranslateTransform(50, 50)
    $g.ScaleTransform(0.74, 0.74)
    $g.MultiplyTransform([System.Drawing.Drawing2D.Matrix]::new(1, 0, -0.14, 1, 0, 0))
    $g.TranslateTransform(-51, -51)
    $j = [System.Drawing.PointF[]]@(
      (New-Point 30 18), (New-Point 46 18), (New-Point 46 72), (New-Point 38 84), (New-Point 14 84),
      (New-Point 8 76), (New-Point 8 60), (New-Point 23 60), (New-Point 23 70), (New-Point 30 70))
    $t = [System.Drawing.PointF[]]@(
      (New-Point 52 18), (New-Point 94 18), (New-Point 94 34), (New-Point 81 34),
      (New-Point 81 84), (New-Point 65 84), (New-Point 65 34), (New-Point 52 34))
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new((New-Point 0 18), (New-Point 0 84), $monoLetterTop, $monoLetterLow)
    $g.FillPolygon($brush, $j)
    $g.FillPolygon($brush, $t)
  } finally { $g.Dispose() }
  return $bmp
}

# Volledig logo (vanaf 48 px in de .ico), zelfde schaling als assets/jt/icon.png.
function New-FullLogo([int]$size) {
  $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $src = [System.Drawing.Image]::FromFile((Join-Path $srcDir 'Favicon_JT-Streaming.png'))
  try {
    Set-Quality $g
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($src, 0, 0, $size, $size)
  } finally { $g.Dispose(); $src.Dispose() }
  return $bmp
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
  $ms = [IO.MemoryStream]::new()
  try { $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); return , $ms.ToArray() } finally { $ms.Dispose(); $bmp.Dispose() }
}

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$target) {
  [IO.File]::WriteAllBytes("$target.tmp", (Get-PngBytes $bmp))
  return Write-IfChanged "$target.tmp" $target
}

# ICO met PNG-lagen (Windows Vista+ en alle browsers). $layers: @(@{ Size = 16; Png = [byte[]] }, ...).
function Write-Ico([object[]]$layers, [string]$target) {
  $ms = [IO.MemoryStream]::new()
  $w = [IO.BinaryWriter]::new($ms)
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$layers.Count)
  $offset = 6 + 16 * $layers.Count
  foreach ($l in $layers) {
    $dim = if ($l.Size -ge 256) { 0 } else { $l.Size }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$l.Png.Length); $w.Write([uint32]$offset)
    $offset += $l.Png.Length
  }
  foreach ($l in $layers) { $w.Write($l.Png) }
  $w.Flush()
  [IO.File]::WriteAllBytes("$target.tmp", $ms.ToArray())
  $w.Dispose()
  return Write-IfChanged "$target.tmp" $target
}

$monoSource = Join-Path $srcDir 'Favicon_JT-Streaming-monogram.png'
if (Save-Png (New-Monogram 512) $monoSource) { Write-Host 'assets/jt/source/Favicon_JT-Streaming-monogram.png bijgewerkt.' }

# web/favicon.png (32 px, monogram) vervangt de versie van icons_launcher.
if (Save-Png (New-Monogram 32) (Join-Path $repo 'web\favicon.png')) { Write-Host 'web/favicon.png bijgewerkt.' }

# Eén .ico voor web en de Windows-runner: 16/32 monogram, 48/64/256 volledig logo.
$icoLayers = @(
  @{ Size = 16;  Png = (Get-PngBytes (New-Monogram 16)) }
  @{ Size = 32;  Png = (Get-PngBytes (New-Monogram 32)) }
  @{ Size = 48;  Png = (Get-PngBytes (New-FullLogo 48)) }
  @{ Size = 64;  Png = (Get-PngBytes (New-FullLogo 64)) }
  @{ Size = 256; Png = (Get-PngBytes (New-FullLogo 256)) }
)
foreach ($ico in 'web\favicon.ico', 'windows\runner\resources\app_icon.ico') {
  if (Write-Ico $icoLayers (Join-Path $repo $ico)) { Write-Host "$($ico -replace '\\', '/') bijgewerkt." }
}

# 4. Achtergrond van de aanmeldpagina (JtTheme.loginBackgroundAsset): 1600 px breed, JPEG.
#    System.Drawing kan geen WebP schrijven, en een PNG van deze foto blijft ruim boven 1 MB.
$bgTarget = Join-Path $repo 'assets\jt\login_background.jpg'
$bgWidth = 1600
$bgQuality = 80
$src = [System.Drawing.Image]::FromFile((Join-Path $srcDir 'Logo_JT-Streaming.png'))
try {
  $bgHeight = [int][Math]::Round($src.Height * $bgWidth / $src.Width)
  $bmp = [System.Drawing.Bitmap]::new($bgWidth, $bgHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    Set-Quality $g
    $g.DrawImage($src, 0, 0, $bgWidth, $bgHeight)
  } finally { $g.Dispose() }
  $jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
  $params = [System.Drawing.Imaging.EncoderParameters]::new(1)
  $params.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::Quality, [long]$bgQuality)
  try { $bmp.Save("$bgTarget.tmp", $jpeg, $params) } finally { $bmp.Dispose() }
} finally { $src.Dispose() }
if (Write-IfChanged "$bgTarget.tmp" $bgTarget) { Write-Host 'assets/jt/login_background.jpg bijgewerkt.' }
Write-Host "assets/jt/login_background.jpg: $((Get-Item $bgTarget).Length) bytes"

Write-Host 'Iconen gegenereerd.'
