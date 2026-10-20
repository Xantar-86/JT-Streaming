<#
.SYNOPSIS
  Genereert alle JT-Streaming-iconen reproduceerbaar uit de bronlogo's.

.DESCRIPTION
  Bron: assets/jt/source/ (kopieën van de board-logo's, SHA-256 gecontroleerd).
  Uitvoer:
    - assets/jt/icon.png                       (512x512, in-app icoon)
    - web/icons/Icon-*.png                     (icons_launcher, daarna overschreven met New-FullLogo)
    - web/favicon.png                          (32x32)
    - web/favicon.ico, windows/runner/resources/app_icon.ico (lagen 16/32/48/64/256)
    - assets/jt/login_background.jpg           (1600 px breed, achtergrond aanmeldpagina)
    Alle formaten = Favicon_JT-Streaming.png in één stap verkleind (HighQualityBicubic),
    zonder bijsnijden, marge of monogram.
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

# 3. Alle overige formaten komen uit dezelfde resampler (New-FullLogo).
function Set-Quality([System.Drawing.Graphics]$g) {
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
}

# Volledig logo in elk formaat, zelfde schaling als assets/jt/icon.png.
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

# web/favicon.png (32 px) vervangt de versie van icons_launcher.
if (Save-Png (New-FullLogo 32) (Join-Path $repo 'web\favicon.png')) { Write-Host 'web/favicon.png bijgewerkt.' }

# Web-app-iconen: overschrijf de uitvoer van icons_launcher, zodat alle formaten uit één resampler komen.
# Maskable = hetzelfde beeld, zonder extra veilige zone.
foreach ($icon in @(
    @{ Size = 192; File = 'Icon-192.png' }, @{ Size = 512; File = 'Icon-512.png' },
    @{ Size = 192; File = 'Icon-maskable-192.png' }, @{ Size = 512; File = 'Icon-maskable-512.png' })) {
  if (Save-Png (New-FullLogo $icon.Size) (Join-Path $repo "web\icons\$($icon.File)")) { Write-Host "web/icons/$($icon.File) bijgewerkt." }
}

# Eén .ico voor web en de Windows-runner, alle lagen uit het volledige logo.
$icoLayers = foreach ($size in 16, 32, 48, 64, 256) { @{ Size = $size; Png = (Get-PngBytes (New-FullLogo $size)) } }
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
