<#
.SYNOPSIS
  Bouwt de JT-Streaming-Windows-app en de installer (Setup.exe + sha256) in één opdracht.

.DESCRIPTION
  pwsh tool/jt/build-windows.ps1 [-Clean] [-BuildNumber N]

  1. Controleert de Flutter-versie tegen .fvmrc (stopt bij verschil) en het symlink-recht
     (Developer Mode of admin; zonder kan `flutter pub get` de Windows-plugins niet koppelen).
  2. Noteert `git describe --tags --always --dirty` (waarschuwt bij een vuile werkmap).
  3. -Clean: flutter clean.
  4. flutter pub get --enforce-lockfile.
  5. tool/jt/generate-icons.ps1.
  6. flutter build windows --release --build-name <basis>-jt.<N> --build-number <N>.
  7. Wizardafbeeldingen (build/jt-installer/) uit het JT-logo.
  8. Inno Setup (tool/jt/windows_setup-jt.iss) -> dist/JT-Streaming-Windows-<versie>-Setup.exe + .sha256.
  Exitcode 0 bij succes, 1 bij elke fout.

  Flutter wordt gezocht in $env:JT_FLUTTER_ROOT, standaard C:\paperclip\tools\flutter-3.35.7\flutter.
  Inno Setup 6 (ISCC.exe) in $env:JT_ISCC, standaard C:\paperclip\tools\InnoSetup-6.5.4\ISCC.exe,
  anders de standaardinstallatiemappen van Inno Setup 6.
  Vereist Visual Studio (Build Tools) 2022 met de werklast "Desktop development with C++" en
  Rust via rustup (in $env:CARGO_HOME\bin of %USERPROFILE%\.cargo\bin) voor de plugin smtc_windows.
  De installer is niet ondertekend (SmartScreen toont "Onbekende uitgever").
#>
[CmdletBinding()]
param(
  [switch]$Clean,
  [ValidateRange(1, 100000)]
  [int]$BuildNumber = 1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutterRoot = if ($env:JT_FLUTTER_ROOT) { $env:JT_FLUTTER_ROOT } else { 'C:\paperclip\tools\flutter-3.35.7\flutter' }
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'

function Invoke-Native([string]$exe, [string[]]$arguments) {
  Write-Host "> $(Split-Path -Leaf $exe) $($arguments -join ' ')"
  & $exe @arguments
  if ($LASTEXITCODE -ne 0) { throw "$(Split-Path -Leaf $exe) $($arguments -join ' ') faalde (exit $LASTEXITCODE)" }
}

function Test-SymlinkSupport {
  $dir = Join-Path ([IO.Path]::GetTempPath()) "jt-symlink-$PID"
  New-Item -ItemType Directory -Force $dir | Out-Null
  try {
    New-Item -ItemType SymbolicLink -Path (Join-Path $dir 'l') -Target $dir -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  } finally {
    Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
  }
}

function Find-Iscc {
  $candidates = @(
    $env:JT_ISCC,
    'C:\paperclip\tools\InnoSetup-6.5.4\ISCC.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  throw 'Inno Setup 6 (ISCC.exe) niet gevonden (zet $env:JT_ISCC)'
}

# Wizardafbeelding: JT-logo gecentreerd op de donkere JT-achtergrond (maten volgens Inno Setup, WizardStyle=modern).
function New-WizardImage([string]$logo, [string]$target, [int]$width, [int]$height) {
  $src = [System.Drawing.Image]::FromFile($logo)
  try {
    $bmp = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    try {
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::FromArgb(0x1B, 0x1B, 0x1F))
        $size = [int]($width * 0.8)
        $g.DrawImage($src, [int](($width - $size) / 2), [int](($height - $size) / 2), $size, $size)
      } finally { $g.Dispose() }
      $bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Bmp)
    } finally { $bmp.Dispose() }
  } finally { $src.Dispose() }
}

try {
  Push-Location $repo
  if (-not (Test-Path $flutter)) { throw "Flutter niet gevonden: $flutter (zet `$env:JT_FLUTTER_ROOT)" }
  $env:PATH = "$(Join-Path $flutterRoot 'bin');$env:PATH"
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
  $iscc = Find-Iscc
  # Rust (rustup + cargo) voor de cargokit-plugin smtc_windows; upstream-CI heeft Rust al op de runner.
  $cargoBin = if ($env:CARGO_HOME) { Join-Path $env:CARGO_HOME 'bin' } else { Join-Path $env:USERPROFILE '.cargo\bin' }
  if (Test-Path $cargoBin) { $env:PATH = "$cargoBin;$env:PATH" }
  if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) { throw 'rustup niet gevonden (nodig voor smtc_windows): installeer Rust via rustup-init' }
  Write-Host "Rust: $((& rustc --version) -join ' ')"

  # 1. Flutter-versie en symlink-recht
  $wanted = (Get-Content -Raw '.fvmrc' | ConvertFrom-Json).flutter
  $versionOut = (& $flutter --version --machine) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw 'flutter --version faalde' }
  $installed = ($versionOut.Substring($versionOut.IndexOf('{')) | ConvertFrom-Json).frameworkVersion
  if ($installed -ne $wanted) { throw "Flutter $installed geïnstalleerd, .fvmrc vraagt $wanted" }
  Write-Host "Flutter $installed (= .fvmrc)"
  if (-not (Test-SymlinkSupport)) { throw 'Geen symlink-recht: zet Developer Mode aan (of bouw als admin)' }
  $config = (& $flutter config --list) -join "`n"
  if ($config -match 'enable-windows-desktop:\s*false') { Invoke-Native $flutter @('config', '--enable-windows-desktop') }

  # 2. Git-stand
  $describe = (git describe --tags --always --dirty).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'git describe faalde' }
  $commit = (git rev-parse HEAD).Trim()
  $status = git status --porcelain
  if ($status) { Write-Warning "Werkmap is niet schoon:`n$($status -join "`n")" }
  Write-Host "Bron: $describe ($commit)"

  # Versie: <upstream-basis>-jt.<N>
  $pubVersion = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
  $buildName = "$pubVersion-jt.$BuildNumber"
  Write-Host "Versie: $buildName (build $BuildNumber)"

  # 3. Clean
  if ($Clean) { Invoke-Native $flutter @('clean') }

  # 4. Dependencies
  Invoke-Native $flutter @('pub', 'get', '--enforce-lockfile')

  # 5. Iconen
  & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'generate-icons.ps1')
  if ($LASTEXITCODE -ne 0) { throw "generate-icons.ps1 faalde (exit $LASTEXITCODE)" }

  # 6. Bouw
  Invoke-Native $flutter @('build', 'windows', '--release', '--build-name', $buildName, '--build-number', "$BuildNumber")
  $release = Join-Path $repo 'build\windows\x64\runner\Release'
  if (-not (Test-Path (Join-Path $release 'JT-Streaming.exe'))) { throw 'JT-Streaming.exe ontbreekt na de bouw' }

  # 7. Wizardafbeeldingen
  Add-Type -AssemblyName System.Drawing
  $wizard = Join-Path $repo 'build\jt-installer'
  New-Item -ItemType Directory -Force $wizard | Out-Null
  $logo = Join-Path $repo 'assets\jt\source\Favicon_JT-Streaming.png'
  foreach ($img in @(@(100, 164, 314), @(125, 192, 386), @(150, 246, 459))) {
    New-WizardImage $logo (Join-Path $wizard "jt-installer-$($img[0]).bmp") $img[1] $img[2]
  }

  # 8. Installer + sha256
  $dist = Join-Path $repo 'dist'
  New-Item -ItemType Directory -Force $dist | Out-Null
  Set-Content -Encoding ascii -LiteralPath (Join-Path $dist '.gitignore') -Value '*'
  $setupBase = "JT-Streaming-Windows-$buildName-Setup"
  $setup = Join-Path $dist "$setupBase.exe"
  if (Test-Path $setup) { Remove-Item -Force $setup }
  Invoke-Native $iscc @('/Q', "/DJT_VERSION=$buildName", "/DJT_OUTPUT_DIR=$dist", "/DJT_OUTPUT_NAME=$setupBase", (Join-Path $PSScriptRoot 'windows_setup-jt.iss'))
  if (-not (Test-Path $setup)) { throw "$setupBase.exe ontbreekt na Inno Setup" }
  $hash = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLowerInvariant()
  Set-Content -Encoding ascii -NoNewline -LiteralPath "$setup.sha256" -Value "$hash  $setupBase.exe`n"

  Write-Host ''
  Write-Host "OK: $setup"
  Write-Host "SHA-256: $hash"
  $exitCode = 0
} catch {
  Write-Host "FOUT: $($_.Exception.Message)" -ForegroundColor Red
  $exitCode = 1
} finally {
  Pop-Location -ErrorAction SilentlyContinue
}
exit $exitCode
