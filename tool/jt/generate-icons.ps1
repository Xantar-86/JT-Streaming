<#
.SYNOPSIS
  Genereert alle JT-Streaming-iconen reproduceerbaar uit de bronlogo's.

.DESCRIPTION
  Bron: assets/jt/source/ (kopieën van de board-logo's, SHA-256 gecontroleerd).
  Uitvoer:
    - assets/jt/icon.png                       (512x512, in-app icoon)
    - web/favicon.png, web/icons/Icon-*.png    (icons_launcher)
    - windows/runner/resources/app_icon.ico    (icons_launcher)
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

Write-Host 'Iconen gegenereerd.'
