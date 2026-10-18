<#
.SYNOPSIS
  Bouwt de JT-Streaming-webversie en de Docker-build-context (tar + sha256) in één opdracht.

.DESCRIPTION
  pwsh tool/jt/build-web.ps1 [-Clean] [-BuildNumber N]

  1. Controleert de Flutter-versie tegen .fvmrc (stopt bij verschil).
  2. Noteert `git describe --tags --always --dirty` (waarschuwt bij een vuile werkmap).
  3. -Clean: flutter clean.
  4. flutter pub get --enforce-lockfile (reproduceerbaar: pubspec.lock pint ook de git-dependencies).
  5. tool/jt/generate-icons.ps1.
  6. flutter build web --release --build-name <basis>-jt.<N> --build-number <N>.
  7. LICENSE -> build/web/LICENSE.txt, build/web/jt-buildinfo.json.
  8. dist/jt-streaming-web/ (build/web, upstream-Dockerfile, docker-entrypoint.sh, LICENSE,
     README-deploy.md, BUILDINFO.txt) -> dist/jt-streaming-web-<versie>.tar + .sha256.
  Exitcode 0 bij succes, 1 bij elke fout.

  Flutter wordt gezocht in $env:JT_FLUTTER_ROOT, standaard C:\paperclip\tools\flutter-3.35.7\flutter.

  Zonder symlink-rechten (geen Developer Mode/admin op Windows) kan `flutter pub get` geen
  plugin-symlinks voor desktopplatforms maken. Het script zet dan de desktop-feature-flags van
  Flutter tijdelijk uit (alleen web wordt gebouwd) en zet ze daarna terug.
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
$restoreFlags = @()

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

try {
  Push-Location $repo
  if (-not (Test-Path $flutter)) { throw "Flutter niet gevonden: $flutter (zet `$env:JT_FLUTTER_ROOT)" }
  $env:PATH = "$(Join-Path $flutterRoot 'bin');$env:PATH"
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

  # 1. Flutter-versie
  $wanted = (Get-Content -Raw '.fvmrc' | ConvertFrom-Json).flutter
  $versionOut = (& $flutter --version --machine) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw 'flutter --version faalde' }
  $installed = ($versionOut.Substring($versionOut.IndexOf('{')) | ConvertFrom-Json).frameworkVersion
  if ($installed -ne $wanted) { throw "Flutter $installed geïnstalleerd, .fvmrc vraagt $wanted" }
  Write-Host "Flutter $installed (= .fvmrc)"

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

  # Desktop-flags tijdelijk uit zonder symlink-rechten
  if (-not (Test-SymlinkSupport)) {
    $config = (& $flutter config --list) -join "`n"
    foreach ($platform in 'windows', 'linux', 'macos') {
      if ($config -notmatch "enable-$platform-desktop:\s*false") {
        Invoke-Native $flutter @('config', "--no-enable-$platform-desktop")
        $restoreFlags += $platform
      }
    }
    if ($restoreFlags) { Write-Warning "Geen symlink-rechten: desktop-flags tijdelijk uit ($($restoreFlags -join ', '))." }
  }

  # 3. Clean
  if ($Clean) { Invoke-Native $flutter @('clean') }

  # 4. Dependencies
  Invoke-Native $flutter @('pub', 'get', '--enforce-lockfile')

  # 5. Iconen
  & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'generate-icons.ps1')
  if ($LASTEXITCODE -ne 0) { throw "generate-icons.ps1 faalde (exit $LASTEXITCODE)" }

  # 6. Bouw
  Invoke-Native $flutter @('build', 'web', '--release', '--build-name', $buildName, '--build-number', "$BuildNumber")
  $web = Join-Path $repo 'build\web'
  if (-not (Test-Path (Join-Path $web 'index.html'))) { throw 'build/web/index.html ontbreekt na de bouw' }

  # 7. Licentie en buildinfo in de webapp
  Copy-Item -Force 'LICENSE' (Join-Path $web 'LICENSE.txt')
  $buildInfo = [ordered]@{
    name           = 'JT-Streaming'
    version        = $buildName
    buildNumber    = $BuildNumber
    source         = $describe
    commit         = $commit
    flutter        = $installed
    upstream       = 'Fladder (DonutWare), GPL-3.0'
    builtAtUtc     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $buildInfo | ConvertTo-Json | Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $web 'jt-buildinfo.json')

  # 8. Build-context + tar + sha256
  $dist = Join-Path $repo 'dist'
  New-Item -ItemType Directory -Force $dist | Out-Null
  Set-Content -Encoding ascii -LiteralPath (Join-Path $dist '.gitignore') -Value '*'
  $ctx = Join-Path $dist 'jt-streaming-web'
  if (Test-Path $ctx) { Remove-Item -Recurse -Force $ctx }
  New-Item -ItemType Directory -Force (Join-Path $ctx 'build') | Out-Null
  Copy-Item -Recurse $web (Join-Path $ctx 'build\web')
  Copy-Item 'Dockerfile', 'docker-entrypoint.sh', 'LICENSE' $ctx
  Copy-Item (Join-Path $PSScriptRoot 'README-deploy.md') (Join-Path $ctx 'README-deploy.md')
  ($buildInfo.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $ctx 'BUILDINFO.txt')

  $entry = [IO.File]::ReadAllBytes((Join-Path $ctx 'docker-entrypoint.sh'))
  if ($entry -contains 13) { throw 'docker-entrypoint.sh bevat CR-tekens; de container zou niet starten' }

  $tarName = "jt-streaming-web-$buildName.tar"
  $tar = Join-Path $dist $tarName
  if (Test-Path $tar) { Remove-Item -Force $tar }
  Invoke-Native "$env:SystemRoot\System32\tar.exe" @('-cf', $tar, '-C', $ctx, '.')
  $hash = (Get-FileHash -Algorithm SHA256 $tar).Hash.ToLowerInvariant()
  Set-Content -Encoding ascii -NoNewline -LiteralPath "$tar.sha256" -Value "$hash  $tarName`n"

  Write-Host ''
  Write-Host "OK: $tar"
  Write-Host "SHA-256: $hash"
  $exitCode = 0
} catch {
  Write-Host "FOUT: $($_.Exception.Message)" -ForegroundColor Red
  $exitCode = 1
} finally {
  foreach ($platform in $restoreFlags) {
    & $flutter config "--enable-$platform-desktop" | Out-Null
  }
  Pop-Location -ErrorAction SilentlyContinue
}
exit $exitCode
