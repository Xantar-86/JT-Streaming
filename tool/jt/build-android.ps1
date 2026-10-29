<#
.SYNOPSIS
  Bouwt de gesigneerde JT-Streaming-apk's voor Android TV (één per ABI: armeabi-v7a en arm64-v8a) in één opdracht.

.DESCRIPTION
  pwsh tool/jt/build-android.ps1 [-Clean] [-JtVersion 5.1] [-VersionCode N] [-OutDir <map>] [-Universal]

  1. Controleert de Flutter-versie tegen .fvmrc, zoekt JDK 17 en de Android SDK.
  2. Noteert `git describe --tags --always --dirty` (waarschuwt bij een vuile werkmap).
  3. Haalt de release-keystore op (zie *Keystore*) en schrijft android/app/keystore.jks +
     android/app/key.properties. Beide zijn gitignored en worden na de bouw altijd gewist.
  4. -Clean: flutter clean. Daarna flutter pub get --enforce-lockfile en tool/jt/generate-icons.ps1.
  5. flutter build apk --release --flavor production --build-name <basis>-jt.<JtVersion> --build-number <VersionCode>
     --split-per-abi --target-platform android-arm,android-arm64 (zonder de laatste twee met -Universal).
  6. Controle per apk, faalt bij elke afwijking:
     - apksigner: certificaat-SHA-256 = dat van de release-keystore (nooit de debug-sleutel);
     - aapt2 badging: package be.thoelen.jtstreaming, label JT-Streaming, versionName, versionCode,
       leanback-launcher, banner, icoon, native code precies die ABI (universeel: minstens
       armeabi-v7a en arm64-v8a), niet debuggable.
  7. Kopie naar <OutDir>/JT-Streaming-AndroidTV-<versie>-<abi>.apk + .sha256
     (universeel: JT-Streaming-AndroidTV-<versie>.apk).
  Exitcode 0 bij succes, 1 bij elke fout.

  build-number = 1000 x jt-nummer + subnummer (jt.5.1 = 5001, jt.6 = 6000), tenzij -VersionCode.
  versionCode per ABI-apk = 10 x build-number + 1 (armeabi-v7a) of + 2 (arm64-v8a), zie
  abi-version-code in android/app/build.gradle (jt.6.6: 60061 en 60062, de universele jt.6.5 was 6005).
  Universeel: versionCode = build-number.
  Android installeert een update alleen over een bestaande installatie als de versionCode hoger is
  en dezelfde sleutel signeert. Na een ABI-apk kan een universele apk met een lager getal niet meer
  als update: blijf bij ABI-apk's.

  Keystore: JSON {storeBase64, storePassword, keyAlias, keyPassword}, uit de omgevingsvariabele
  JT_STREAMING_ANDROID_KEYSTORE (company-secret), anders uit het bestand in
  $env:JT_STREAMING_ANDROID_KEYSTORE_FILE, standaard
  C:\paperclip\forge\secrets\jt-streaming\jt_streaming_android_keystore.json.
  Wachtwoorden komen nooit op de opdrachtregel of in de uitvoer.

  Paden: $env:JT_FLUTTER_ROOT (standaard C:\paperclip\tools\flutter-3.35.7\flutter),
  $env:JAVA_HOME (standaard C:\paperclip\tools\jdk-17.0.20.1+1),
  $env:ANDROID_HOME (standaard C:\paperclip\tools\android-sdk).
#>
[CmdletBinding()]
param(
  [switch]$Clean,
  [ValidatePattern('^[0-9]+(\.[0-9]+)?$')]
  [string]$JtVersion = '5.1',
  [ValidateRange(1, 2100000000)]
  [int]$VersionCode = 0,
  [string]$OutDir,
  [switch]$Universal
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutterRoot = if ($env:JT_FLUTTER_ROOT) { $env:JT_FLUTTER_ROOT } else { 'C:\paperclip\tools\flutter-3.35.7\flutter' }
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = 'C:\paperclip\tools\jdk-17.0.20.1+1' }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = 'C:\paperclip\tools\android-sdk' }
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }

$expectedPackage = 'be.thoelen.jtstreaming'
$expectedLabel = 'JT-Streaming'
$requiredAbis = @('armeabi-v7a', 'arm64-v8a')
$appDir = Join-Path $repo 'android\app'
$keyProps = Join-Path $appDir 'key.properties'
$keyStore = Join-Path $appDir 'keystore.jks'
$defaultKeystoreFile = 'C:\paperclip\forge\secrets\jt-streaming\jt_streaming_android_keystore.json'

function Invoke-Native([string]$exe, [string[]]$arguments) {
  Write-Host "> $(Split-Path -Leaf $exe) $($arguments -join ' ')"
  & $exe @arguments
  if ($LASTEXITCODE -ne 0) { throw "$(Split-Path -Leaf $exe) $($arguments -join ' ') faalde (exit $LASTEXITCODE)" }
}

# Nieuwste build-tools (aapt2, apksigner).
function Find-BuildTools {
  $dir = Join-Path $env:ANDROID_HOME 'build-tools'
  if (-not (Test-Path $dir)) { throw "Geen build-tools in $dir (sdkmanager --install build-tools/36.0.0)" }
  $latest = Get-ChildItem $dir -Directory | Sort-Object { [version]($_.Name -replace '-.*$', '') } | Select-Object -Last 1
  if (-not $latest) { throw "Geen build-tools in $dir" }
  return $latest.FullName
}

function Get-KeystoreSecret {
  if ($env:JT_STREAMING_ANDROID_KEYSTORE) {
    Write-Host 'Keystore: uit $env:JT_STREAMING_ANDROID_KEYSTORE'
    $raw = $env:JT_STREAMING_ANDROID_KEYSTORE
  } else {
    $file = if ($env:JT_STREAMING_ANDROID_KEYSTORE_FILE) { $env:JT_STREAMING_ANDROID_KEYSTORE_FILE } else { $defaultKeystoreFile }
    if (-not (Test-Path -LiteralPath $file)) { throw "Geen keystore: zet `$env:JT_STREAMING_ANDROID_KEYSTORE of maak $file" }
    Write-Host "Keystore: uit $file"
    $raw = Get-Content -Raw -LiteralPath $file
  }
  $secret = $raw | ConvertFrom-Json
  foreach ($field in 'storeBase64', 'storePassword', 'keyAlias', 'keyPassword') {
    if (-not ($secret.PSObject.Properties.Name -contains $field) -or -not $secret.$field) { throw "Keystore-JSON mist veld '$field'" }
  }
  return $secret
}

# Java-properties-escaping voor key.properties.
function ConvertTo-PropertyValue([string]$value) {
  return ($value -replace '\\', '\\' -replace '([:=#!])', '\$1')
}

# SHA-256 van het certificaat in de keystore (hex, kleine letters, zonder dubbele punten).
function Get-KeystoreCertSha256([string]$storeFile, $secret) {
  $env:JT_KS_STOREPASS = $secret.storePassword
  try {
    $out = & (Join-Path $env:JAVA_HOME 'bin\keytool.exe') -list -v -keystore $storeFile -alias $secret.keyAlias -storepass:env JT_KS_STOREPASS 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'keytool -list faalde (verkeerd wachtwoord of alias?)' }
  } finally { Remove-Item Env:JT_KS_STOREPASS -ErrorAction SilentlyContinue }
  $line = $out | Where-Object { $_ -match '^\s*SHA256:\s*([0-9A-F:]+)' } | Select-Object -First 1
  if (-not $line) { throw 'Geen SHA256 in keytool-uitvoer' }
  return ([regex]::Match($line, '([0-9A-F]{2}(:[0-9A-F]{2}){31})').Value -replace ':', '').ToLowerInvariant()
}

function Remove-SigningFiles {
  foreach ($f in $keyProps, $keyStore) {
    if (Test-Path -LiteralPath $f) { Remove-Item -Force -LiteralPath $f }
  }
}

try {
  Push-Location $repo
  if (-not (Test-Path $flutter)) { throw "Flutter niet gevonden: $flutter (zet `$env:JT_FLUTTER_ROOT)" }
  if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) { throw "JDK niet gevonden in $env:JAVA_HOME" }
  $env:PATH = "$(Join-Path $flutterRoot 'bin');$(Join-Path $env:JAVA_HOME 'bin');$env:PATH"
  $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
  $buildTools = Find-BuildTools
  $aapt2 = Join-Path $buildTools 'aapt2.exe'
  $apksigner = Join-Path $buildTools 'apksigner.bat'
  Write-Host "JDK: $env:JAVA_HOME"
  Write-Host "Android SDK: $env:ANDROID_HOME (build-tools $(Split-Path -Leaf $buildTools))"

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

  # Versie: <upstream-basis>-jt.<JtVersion>, versionCode = 1000 x hoofd + sub
  $pubVersion = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches[0].Groups[1].Value
  $buildName = "$pubVersion-jt.$JtVersion"
  if ($VersionCode -eq 0) {
    $parts = $JtVersion.Split('.')
    $VersionCode = 1000 * [int]$parts[0] + $(if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 })
  }
  Write-Host "Versie: $buildName (versionCode $VersionCode)"

  # 3. Keystore (tijdelijk, gitignored)
  foreach ($f in 'android/app/key.properties', 'android/app/keystore.jks') {
    git check-ignore -q $f
    if ($LASTEXITCODE -ne 0) { throw "$f is niet gitignored: keystore niet geschreven" }
  }
  $secret = Get-KeystoreSecret
  Remove-SigningFiles
  [IO.File]::WriteAllBytes($keyStore, [Convert]::FromBase64String($secret.storeBase64))
  $props = @(
    "storePassword=$(ConvertTo-PropertyValue $secret.storePassword)",
    "keyPassword=$(ConvertTo-PropertyValue $secret.keyPassword)",
    "keyAlias=$(ConvertTo-PropertyValue $secret.keyAlias)"
  ) -join "`n"
  [IO.File]::WriteAllText($keyProps, "$props`n", [Text.UTF8Encoding]::new($false))
  $expectedCert = Get-KeystoreCertSha256 $keyStore $secret
  $secret = $null
  Write-Host "Release-certificaat SHA-256: $expectedCert"

  # 4. Clean, dependencies, iconen
  if ($Clean) { Invoke-Native $flutter @('clean') }
  Invoke-Native $flutter @('pub', 'get', '--enforce-lockfile')
  & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'generate-icons.ps1')
  if ($LASTEXITCODE -ne 0) { throw "generate-icons.ps1 faalde (exit $LASTEXITCODE)" }

  # 5. Bouw. Standaard één apk per ABI (--split-per-abi, alleen ARM: x86_64 is enkel voor de emulator);
  #    -Universal: één apk met armeabi-v7a, arm64-v8a en x86_64 (zoals t/m jt.6.5).
  $buildArgs = @('build', 'apk', '--release', '--flavor', 'production',
    '--build-name', $buildName, '--build-number', "$VersionCode")
  if (-not $Universal) { $buildArgs += @('--split-per-abi', '--target-platform', 'android-arm,android-arm64') }
  try {
    Invoke-Native $flutter $buildArgs
  } finally {
    Remove-SigningFiles
  }
  $outputs = Join-Path $repo 'build\app\outputs\flutter-apk'
  # Per apk: bronbestand, naam in OutDir, verwachte ABI's en versionCode (zie abi-version-code in build.gradle).
  $apks = if ($Universal) {
    , @{ File = 'app-production-release.apk'; Name = "JT-Streaming-AndroidTV-$buildName.apk"; Abis = $requiredAbis; Code = $VersionCode }
  } else {
    @{ File = 'app-armeabi-v7a-production-release.apk'; Name = "JT-Streaming-AndroidTV-$buildName-armeabi-v7a.apk"; Abis = @('armeabi-v7a'); Code = 10 * $VersionCode + 1 }
    @{ File = 'app-arm64-v8a-production-release.apk'; Name = "JT-Streaming-AndroidTV-$buildName-arm64-v8a.apk"; Abis = @('arm64-v8a'); Code = 10 * $VersionCode + 2 }
  }

  New-Item -ItemType Directory -Force $OutDir | Out-Null
  if ($OutDir -eq (Join-Path $repo 'dist')) { Set-Content -Encoding ascii -LiteralPath (Join-Path $OutDir '.gitignore') -Value '*' }
  $results = foreach ($a in $apks) {
    $apk = Join-Path $outputs $a.File
    if (-not (Test-Path $apk)) { throw "apk ontbreekt na de bouw: $apk" }
    Write-Host ''
    Write-Host "== $($a.File)"

    # 6a. Signering: alleen de release-sleutel
    $certOut = (& $apksigner verify --verbose --print-certs $apk 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "apksigner verify faalde:`n$certOut" }
    if ($certOut -match 'Android Debug') { throw 'apk is met de debug-sleutel gesigneerd' }
    $signers = [regex]::Matches($certOut, 'certificate SHA-256 digest:\s*([0-9a-f]{64})') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    if (@($signers).Count -ne 1 -or $signers -ne $expectedCert) { throw "Onverwacht certificaat: $($signers -join ', ') (verwacht $expectedCert)" }
    if ($certOut -notmatch 'Verified using v2 scheme \(APK Signature Scheme v2\): true') { throw 'Geen v2-handtekening' }
    Write-Host "Signering OK (release-certificaat $expectedCert)"

    # 6b. Inhoud
    $badging = (& $aapt2 dump badging $apk 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "aapt2 dump badging faalde:`n$badging" }
    $checks = [ordered]@{
      "package $expectedPackage"     = "package: name='$([regex]::Escape($expectedPackage))'"
      "versionName $buildName"       = "versionName='$([regex]::Escape($buildName))'"
      "versionCode $($a.Code)"       = "versionCode='$($a.Code)'"
      "label $expectedLabel"         = "application-label:'$([regex]::Escape($expectedLabel))'"
      'leanback-launcher'            = 'leanback-launchable-activity:'
      'banner'                       = "application: .*banner='[^']+'"
      'icoon'                        = "application: .*icon='[^']+'"
    }
    foreach ($c in $checks.GetEnumerator()) {
      if ($badging -notmatch $c.Value) { throw "Badging-controle faalt: $($c.Key)" }
    }
    if ($badging -match 'application-debuggable') { throw 'apk is debuggable' }
    $nativeCode = [regex]::Match($badging, "native-code:(.*)").Groups[1].Value
    foreach ($abi in $a.Abis) {
      if ($nativeCode -notmatch "'$abi'") { throw "ABI $abi ontbreekt (native-code:$nativeCode)" }
    }
    $found = @([regex]::Matches($nativeCode, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    if ($found.Count -ne $a.Abis.Count) { throw "Onverwachte ABI's (native-code:$nativeCode, verwacht $($a.Abis -join ', '))" }
    Write-Host "Badging OK: $expectedPackage, $expectedLabel, $buildName, versionCode $($a.Code), leanback, banner, ABI's$nativeCode"

    # 7. Kopie + sha256
    $target = Join-Path $OutDir $a.Name
    Copy-Item -Force $apk $target
    $hash = (Get-FileHash -Algorithm SHA256 $target).Hash.ToLowerInvariant()
    Set-Content -Encoding ascii -NoNewline -LiteralPath "$target.sha256" -Value "$hash  $($a.Name)`n"
    [pscustomobject]@{ Target = $target; Hash = $hash; Code = $a.Code }
  }

  Write-Host ''
  foreach ($r in $results) {
    Write-Host "OK: $($r.Target) (versionCode $($r.Code))"
    Write-Host "SHA-256: $($r.Hash)"
  }
  $exitCode = 0
} catch {
  Write-Host "FOUT: $($_.Exception.Message)" -ForegroundColor Red
  $exitCode = 1
} finally {
  Remove-SigningFiles
  Pop-Location -ErrorAction SilentlyContinue
}
exit $exitCode
