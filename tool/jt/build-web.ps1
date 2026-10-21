<#
.SYNOPSIS
  Bouwt de JT-Streaming-webversie en de Docker-build-context (tar + sha256) in één opdracht.

.DESCRIPTION
  pwsh tool/jt/build-web.ps1 [-Clean] [-BuildNumber N] [-JtVersion 5.2]

  1. Controleert de Flutter-versie tegen .fvmrc (stopt bij verschil).
  2. Noteert `git describe --tags --always --dirty` (waarschuwt bij een vuile werkmap).
  3. -Clean: flutter clean.
  4. flutter pub get --enforce-lockfile (reproduceerbaar: pubspec.lock pint ook de git-dependencies).
  5. tool/jt/generate-icons.ps1.
  6. flutter build web --release --build-name <basis>-jt.<JtVersion of N> --build-number <N>.
     -JtVersion (bv. 5.2) zet alleen het versielabel; zonder -JtVersion is het label jt.<N>.
     --dart-define=JT_BUILD_ID=<versie>+<N> (versiecheck in de webapp, lib/jt/web/).
     Daarna nabewerking van build/web/flutter_service_worker.js (Update-ServiceWorker, zie hieronder).
  7. LICENSE -> build/web/LICENSE.txt, build/web/jt-buildinfo.json (met buildId).
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
  [int]$BuildNumber = 1,
  [ValidatePattern('^[0-9]+(\.[0-9]+)?$')]
  [string]$JtVersion
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

# Service worker (WP2.8b): Flutter's flutter_service_worker.js serves flutter_bootstrap.js and main.dart.js
# cache-first, so the first load after a deployment still runs the old bundle and nothing reloads the tab.
# Three small changes, each anchored on the exact Flutter 3.35.7 text (the build stops when an anchor is gone):
#  1. activate: when RESOURCES differ from the saved manifest, start from an empty cache (no reuse of old
#     entries) and, after clients.claim(), reload the open tabs so they get the new bundle;
#  2. lazy fetches revalidate (cache: 'no-cache'), so a heuristically fresh HTTP-cache copy of an old file
#     (nginx sends no Cache-Control) cannot end up in the new cache;
#  3. a header comment with the build id.
function Update-ServiceWorker([string]$file, [string]$buildId) {
  $sw = [IO.File]::ReadAllText($file).Replace("`r`n", "`n")
  $patches = @(
    @{
      old = "      var manifest = await manifestCache.match('manifest');`n"
      new = "      var manifest = await manifestCache.match('manifest');`n" +
            "      // JT-Streaming: another bundle starts from an empty cache and reloads the open tabs.`n" +
            "      var jtChanged = false;`n" +
            "      if (manifest) {`n" +
            "        jtChanged = (await manifest.clone().text()) !== JSON.stringify(RESOURCES);`n" +
            "        if (jtChanged) manifest = null;`n" +
            "      }`n"
    },
    @{
      old = "        // Claim client to enable caching on first launch`n        self.clients.claim();`n        return;`n"
      new = "        // Claim client to enable caching on first launch`n        await self.clients.claim();`n" +
            "        // After activation (navigate() inside waitUntil would wait for this activation).`n        if (jtChanged) setTimeout(jtReloadClients, 100);`n        return;`n"
    },
    @{
      old = "return response || fetch(event.request).then((response) => {"
      new = "return response || fetch(new Request(event.request, {'cache': 'no-cache'})).then((response) => {"
    }
  )
  foreach ($p in $patches) {
    $count = ([regex]::Matches($sw, [regex]::Escape($p.old))).Count
    if ($count -ne 1) { throw "flutter_service_worker.js: anker $count keer gevonden (verwacht 1): $($p.old.Trim())" }
    $sw = $sw.Replace($p.old, $p.new)
  }
  $sw = "// JT-Streaming $buildId, patched by tool/jt/build-web.ps1 (see CUSTOMIZING.md, service worker)`n" + $sw +
    "`n// JT-Streaming: reload the open tabs after an update so they run the new bundle.`n" +
    "async function jtReloadClients() {`n" +
    "  const clients = await self.clients.matchAll({type: 'window'});`n" +
    "  for (const client of clients) {`n" +
    "    try {`n" +
    "      await client.navigate(client.url);`n" +
    "    } catch (e) {`n" +
    "      console.warn('[jt-sw] reload of an open tab failed', e);`n" +
    "    }`n" +
    "  }`n" +
    "}`n"
  [IO.File]::WriteAllText($file, $sw, [Text.UTF8Encoding]::new($false))
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

  # Versie: <upstream-basis>-jt.<JtVersion of N>
  $pubVersion = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
  $buildName = "$pubVersion-jt.$(if ($JtVersion) { $JtVersion } else { $BuildNumber })"
  $buildId = "$buildName+$BuildNumber"
  Write-Host "Versie: $buildName (build $BuildNumber, build id $buildId)"

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
  Invoke-Native $flutter @('build', 'web', '--release', '--build-name', $buildName, '--build-number', "$BuildNumber",
    "--dart-define=JT_BUILD_ID=$buildId")
  $web = Join-Path $repo 'build\web'
  if (-not (Test-Path (Join-Path $web 'index.html'))) { throw 'build/web/index.html ontbreekt na de bouw' }
  Update-ServiceWorker (Join-Path $web 'flutter_service_worker.js') $buildId
  Write-Host 'flutter_service_worker.js nabewerkt (JT-update)'

  # 7. Licentie en buildinfo in de webapp
  Copy-Item -Force 'LICENSE' (Join-Path $web 'LICENSE.txt')
  $buildInfo = [ordered]@{
    name           = 'JT-Streaming'
    version        = $buildName
    buildNumber    = $BuildNumber
    buildId        = $buildId
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
