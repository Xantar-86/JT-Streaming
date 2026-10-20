# JT-Streaming aanpassen

JT-Streaming is Fladder (DonutWare, GPL-3.0) met een dunne eigen laag erbovenop.
Vuistregel: **een wijziging aan de interface raakt meestal één bestand: `lib/jt/jt_theme.dart`.**

## Waar staat wat

| Map/bestand | Inhoud |
|---|---|
| `lib/jt/` | Alle eigen code (thema, naam, startscherm, standaardinstellingen) |
| `assets/jt/` | Logo's (© fam. Thoelen, niet onder GPL) |
| `tool/jt/` | Bouw- en icoonscripts |
| `third_party/media_kit/` | Gevendorde media_kit met JT-patch (web-HLS altijd via hls.js), zie `JT-PATCH.md` daar |

## Wil je X veranderen, dan pas je Y aan

Alles hieronder is één regel in **`lib/jt/jt_theme.dart`**, gevolgd door één rebuild
(`pwsh tool/jt/build-web.ps1`).

| Wil je ... | Pas aan in `lib/jt/jt_theme.dart` | Voorbeeld |
|---|---|---|
| de accentkleur (accentlijn, knoppen, focus) | `accent` | `static const Color accent = Color(0xFF2E7DFF);` |
| dat de systeemkleur van Windows/Android wél gebruikt wordt | `overrideSystemAccent` | `false` |
| de Material-3-afgeleide tint i.p.v. de exacte accentkleur | `exactAccent` | `false` |
| een andere kleurvariant (vaster dan de gebruikersinstelling) | `schemeVariant` | `DynamicSchemeVariant.vibrant` |
| een andere achtergrond achter zenderlogo's | `channelTileBackground` | `Color(0xFF1B1B1F)` |
| rondere of hoekigere kaarten en knoppen | `radiusSmall`, `radiusDefault`, `radiusLarge` | `radiusSmall = 4` |
| meer of minder ruimte tussen de rijen van het startscherm | `rowSpacing` | `24` |
| meer of minder rand rond zenderlogo's | `channelLogoPadding` | `8` |
| de **volgorde van de rijen** op het startscherm | volgorde in `homeRows` | `JtHomeRow.continueWatching` bovenaan zetten |
| een rij **verbergen** (bv. "Volgende") | de rij uit `homeRows` weglaten | `JtHomeRow.nextUp` schrappen |
| alleen bepaalde **bibliotheken op het startscherm** | `homeLibrariesOnly` | `['Netflix Series', 'Films (IPTV)']` |
| een bibliotheek nooit op het startscherm | `homeLibrariesHidden` | `['Eigen muziek']` |
| de **tegelverhouding per inhoudstype** | `tileRatio` | `FladderItemType.movie: 0.6` (breedte/hoogte) |
| de tegelverhouding in "Recent toegevoegd" per bibliotheektype | `libraryTileRatio` | `CollectionType.tvshows: 0.6` |
| een ander lettertype | `fontFamily` (+ font in `assets/jt/fonts/` en `pubspec.yaml` `fonts:`) | `'OpenSans'` (zit al in de app) |

Opmerkingen:
- `homeRows` bepaalt alleen de rijen die Fladder toont; welke "Volgende/Verder kijken"-rijen bestaan,
  hangt ook af van de instelling *Startscherm > Volgende* in de app. De banner staat altijd bovenaan.
- De bron van waarheid voor bibliotheken op het startscherm blijft de Jellyfin-gebruikersinstelling
  (volgorde, "Recent toegevoegd" uitsluiten). `homeLibrariesOnly/Hidden` is een extra filter in code.
- Accentkleur `#D88F48`: bepaald uit `Logo_JT-Streaming.png` als gemiddelde van de heldere, verzadigde
  pixels (helderheid > 0,7, verzadiging > 0,55; 99,8 % daarvan ligt in tint 20-40°, amber).
- Een gebruiker die in *Instellingen > Thema* zelf een kleur kiest, ziet die kleur (upstream-gedrag).

### Naam, logo en standaardinstellingen

| Wil je ... | Pas aan |
|---|---|
| de weergavenaam | `lib/jt/jt_brand.dart` → `appName` (de webtitel staat daarnaast in `web/index.html` en `web/manifest.json`) |
| het logo/icoon | vervang de bronbestanden en hashes, zie `tool/jt/generate-icons.ps1 -SourceDir <map>` (zie *Iconen en favicon*) |
| de URL van de fork op het Over-scherm | `lib/jt/jt_brand.dart` → `forkUrl` |
| standaardinstellingen voor nieuwe installaties | `lib/jt/jt_defaults.dart` |

### Achtergrond van de aanmeldpagina

De aanmeldpagina (server kiezen en inloggen) toont `assets/jt/login_background.jpg` paginavullend
(`BoxFit.cover`, gecentreerd; op smalle schermen wordt het beeld bijgesneden), gedempt boven de
achtergrondkleur van het thema. Alle waarden staan in **`lib/jt/jt_theme.dart`**, blok *Aanmeldpagina*:

| Wil je ... | Pas aan | Voorbeeld |
|---|---|---|
| de achtergrond uitzetten (upstream) | `loginBackground` | `false` |
| een ander beeld | `loginBackgroundAsset` (bestand in `assets/jt/`) | `'assets/jt/mijn_beeld.jpg'` |
| het beeld sterker of zwakker tonen | `loginBackgroundOpacity` (0-1) | `0.25` = zwakker, `0.5` = sterker |
| sterker dempen met een extra laag | `loginBackgroundOverlay` (0-1, kleur = themakleur) | `0.6` |
| meer of minder vervaging | `loginBackgroundBlur` (0 = uit) | `6` |

Een ander beeld met dezelfde optimalisatie (1600 px breed, JPEG kwaliteit 80, nu 183 697 bytes):
vervang `assets/jt/source/Logo_JT-Streaming.png` (en de hash in `tool/jt/generate-icons.ps1`) en draai
`pwsh tool/jt/generate-icons.ps1`; daarna één rebuild. Upstream-aanraking: één wrapper
(`JtLoginBackground`, `// JT-HOOK: login-background`) rond de `body` van `lib/screens/login/login_screen.dart`.

### Iconen en favicon

Alles komt uit `pwsh tool/jt/generate-icons.ps1` (ook aangeroepen door `build-web.ps1`); niets met de hand.

| Bestand | Inhoud |
|---|---|
| `web/favicon.png` (32x32) | `Favicon_JT-Streaming.png` verkleind (HighQualityBicubic), geen monogram |
| `web/favicon.ico`, `windows/runner/resources/app_icon.ico` | idem, PNG-lagen 16/32/48/64/256 px |
| `web/icons/Icon-192/512` (+ maskable), apple-touch-icon | idem; overschrijft de uitvoer van icons_launcher, maskable zonder extra veilige zone |

Alle formaten komen in één stap uit hetzelfde bronbestand (`New-FullLogo` in `generate-icons.ps1`),
zonder bijsnijden, marge of eigen ontwerp. Ander icoon: vervang het bronbestand + de hash in het script
en draai het; verhoog daarna de cache-buster `?v=jtN` in `web/index.html` (nu `?v=jt5`, ook op de
apple-touch-link), anders tonen browsers nog het oude icoon.

### Opnemen (DVR) vanuit de tv-gids

Code in `lib/jt/dvr/` (ontwerp: `docs/ontwerp-dvr.md` in de projectmap). Alleen zichtbaar voor gebruikers
met het Jellyfin-recht *Live TV-opnames beheren* (`Policy.EnableLiveTvManagement`); de server dwingt
hetzelfde af. Marges (vooraf/achteraf) komen uit de Live TV-instellingen van de server en worden alleen
getoond. Teksten: sleutels `jtDvr…` achteraan in `lib/l10n/app_en.arb` en `app_nl.arb`. Hooks
(`// JT-HOOK: dvr-…`): `live_tv_screen.dart` (dialoog + knop "Geplande opnames"), `channel_row.dart`
(rood bolletje), `video_player_guide_wrapper.dart` en `channel_program_item.dart` (knoppen).

### Hooks in upstream-bestanden

Elke plek waar een upstream-bestand naar `lib/jt/` verwijst, is gemarkeerd met `// JT-HOOK: <naam>`.
Controle na een rebase: `git grep -c "JT-HOOK"` (verwacht aantal: zie *Upstream binnenhalen*).

## Bouwen

Eén opdracht (PowerShell 7, Windows):

```powershell
pwsh tool/jt/build-web.ps1 -Clean -BuildNumber 1
```

- Vereist Flutter **3.35.7 stable** (de versie uit `.fvmrc`) in `$env:JT_FLUTTER_ROOT`
  (standaard `C:\paperclip\tools\flutter-3.35.7\flutter`). Het script stopt bij een andere versie.
- `flutter pub get --enforce-lockfile`: `pubspec.lock` pint alle dependencies, ook de git-forks.
- Iconen worden telkens opnieuw gegenereerd (`tool/jt/generate-icons.ps1`, idempotent).
- Uitvoer: `build/web/` (met `LICENSE.txt` en `jt-buildinfo.json`) en in `dist/`:
  `jt-streaming-web/` (Docker-build-context met het ongewijzigde upstream-`Dockerfile`),
  `jt-streaming-web-<versie>.tar` en `.tar.sha256`. Versie = `0.11.1-jt.<BuildNumber>`.
- Exitcode ≠ 0 bij elke fout.
- Testnorm: `flutter analyze` geeft 0 meldingen en `flutter test` is volledig groen, **behalve 1 bekend
  rode upstream-test `test/widget_test.dart`** (al rood op upstream `v0.11.1`, "No ProviderScope").
  Dat bestand laten we bewust ongewijzigd (upstream-bestand, minder rebase-conflicten).
- Op een Windows-machine zonder symlink-rechten (geen Developer Mode) zet het script de
  desktop-feature-flags van Flutter tijdelijk uit; voor de webbuild zijn die niet nodig.

### Windows-app en installer

```powershell
pwsh tool/jt/build-windows.ps1 -Clean -BuildNumber 2
```

- Zelfde Flutter-, lockfile- en icoonregels als de webbuild; versie = `0.11.1-jt.<BuildNumber>`.
- Uitvoer: `build/windows/x64/runner/Release/JT-Streaming.exe` en in `dist/`:
  `JT-Streaming-Windows-<versie>-Setup.exe` + `.sha256`. Exitcode ≠ 0 bij elke fout.
- **Bouw in een kort pad** (bv. `C:\src\jt-streaming`), niet in een diepe map of onder `%TEMP%`.
  Vergeet je dat, dan stopt MSBuild met `MSB3491 … exceeds the OS max path limit` (MAX_PATH, 260
  tekens) in `media_kit_libs_windows_video`; gezien bij een repo-pad van ~95 tekens. Daarna kan ook
  `git worktree remove` falen met "Filename too long". Alternatief als het pad lang moet blijven:
  `LongPathsEnabled=1` (register, admin) + `git config core.longpaths true`.
- Vereist op de bouwmachine:
  - **Developer Mode** (of admin): Flutter koppelt de Windows-plugins met symlinks. Het script stopt zonder.
  - **Visual Studio (Build Tools) 2022** met de werklast *Desktop development with C++*
    (`Microsoft.VisualStudio.Workload.VCTools`, incl. recommended) **plus ATL**
    (`Microsoft.VisualStudio.Component.VC.ATL`, voor `flutter_local_notifications_windows`).
  - **Rust via rustup** (`%USERPROFILE%\.cargo\bin` of `$env:CARGO_HOME\bin`), voor de plugin
    `smtc_windows` (cargokit bouwt die uit bron). Per gebruiker te installeren, geen admin nodig.
  - **Inno Setup 6** (`$env:JT_ISCC`, standaard `C:\paperclip\tools\InnoSetup-6.5.4\ISCC.exe`).
- Installer: `tool/jt/windows_setup-jt.iss`, een kopie van upstream `windows/windows_setup.iss`
  (dat bestand blijft ongewijzigd). Eigen `AppId` (`8185C3AD-…`), dus hij staat naast een
  Fladder-installatie; installeert per gebruiker in `%LOCALAPPDATA%\Programs\JT-Streaming`,
  bevat `LICENSE` (GPL-3.0), Nederlands + Engels. De wizardafbeeldingen maakt het script uit het
  JT-logo in `build/jt-installer/`.
- Bij deïnstallatie wordt gevraagd of de app-data weg mag (`%APPDATA%\JT-Streaming (fam. Thoelen)`,
  naam volgt uit `CompanyName`/`ProductName` in `Runner.rc`); stil deïnstalleren laat de data staan.
- De installer is **niet ondertekend**: Windows SmartScreen toont bij de eerste start
  "Windows heeft uw pc beveiligd" / onbekende uitgever (*Meer info → Toch uitvoeren*).

### Wijzigingen aan upstream-bestanden voor Windows (rebase-impact)

| Bestand | Wijziging |
|---|---|
| `windows/CMakeLists.txt` | `BINARY_NAME` → `JT-Streaming` (exe-naam) |
| `windows/runner/main.cpp` | venstertitel bij start → `JT-Streaming` (daarna zet `window_title_provider` `JtBrand.appName`) |
| `windows/runner/Runner.rc` | versie-resource: CompanyName, FileDescription, InternalName, LegalCopyright, OriginalFilename, ProductName |
| `windows/runner/resources/app_icon.ico` | JT-icoon (gegenereerd door `generate-icons.ps1`) |
| `lib/services/notification_service.dart` | `appUserModelId`/`guid` → `JtBrand.windowsAppUserModelId` (`be.thoelen.jtstreaming`) en `JtBrand.windowsNotificationGuid` (2 hooks) |

Bij een conflict in deze bestanden: neem de upstream-versie en zet onze regel(s) er opnieuw in.
Niet gewijzigd: de mpv-venstertitel `nl.jknaapen.fladder` in `lib/wrappers/players/lib_mpv.dart`
(intern, niet zichtbaar) en de Flatpak-id's.

### Android TV-app (apk)

```powershell
pwsh tool/jt/build-android.ps1 -Clean -JtVersion 5.1 -OutDir C:\paperclip\forge\projects\jt-streaming\dist-android
```

- Zelfde Flutter-, lockfile- en icoonregels als de webbuild. Versie = `0.11.1-jt.<JtVersion>`,
  **versionCode = 1000 × jt-nummer + subnummer** (`jt.5.1` = 5001, `jt.6` = 6000; of `-VersionCode N`).
  Android installeert een update alleen over de bestaande app als de versionCode hoger is én dezelfde
  sleutel signeert.
- Uitvoer: `build/app/outputs/flutter-apk/app-production-release.apk`, gekopieerd naar
  `<OutDir>/JT-Streaming-AndroidTV-<versie>.apk` + `.sha256` (standaard `dist/`). Exitcode ≠ 0 bij elke fout.
- **Universele apk** (geen `--split-per-abi`): `armeabi-v7a` (Xiaomi Mi Box S, 32-bit userland),
  `arm64-v8a` (Google TV Streamer 4K) en `x86_64`. Het script faalt als `armeabi-v7a` of `arm64-v8a` ontbreekt.
- **Signering**: release-keystore (RSA 4096, alias `jtstreaming`) als JSON
  `{storeBase64, storePassword, keyAlias, keyPassword}` uit `$env:JT_STREAMING_ANDROID_KEYSTORE`
  (company-secret `jt_streaming_android_keystore`), anders uit het bestand in
  `$env:JT_STREAMING_ANDROID_KEYSTORE_FILE` (standaard
  `C:\paperclip\forge\secrets\jt-streaming\jt_streaming_android_keystore.json`, buiten de repo, ACL alleen
  de bouwgebruiker). Het script schrijft `android/app/key.properties` + `keystore.jks` (gitignored, het
  controleert dat) en wist ze na de bouw, ook bij een fout. Daarna controleert het met `apksigner` dat het
  certificaat exact dat van de keystore is (nooit de debug-sleutel) en met `aapt2 dump badging` package,
  label, versie, leanback-launcher, banner, icoon, ABI's en "niet debuggable".
  **Verlies de keystore niet**: zonder dezelfde sleutel kan een update niet over de bestaande app heen
  (eerst verwijderen = lokale app-instellingen kwijt).
- Vereist op de bouwmachine (alles per gebruiker, geen admin): **JDK 17** (`$env:JAVA_HOME`, standaard
  `C:\paperclip\tools\jdk-17.0.20.1+1`, Temurin-zip) en de **Android SDK** (`$env:ANDROID_HOME`, standaard
  `C:\paperclip\tools\android-sdk`) met `platform-tools`, `build-tools/36.0.0`, `platforms/android-37.0`
  (compileSdk 37), `platforms/android-36` en `ndk/27.0.12077973` (de NDK-versie van Flutter 3.35.7).
  Installeren: `sdkmanager --install "build-tools/36.0.0" "platforms/android-37.0" ...`
  (**met `/`**: de puntkomma-vorm valt in `sdkmanager.bat` uiteen).
  Daarna `flutter config --android-sdk <sdk> --jdk-dir <jdk>`.

### Wijzigingen aan upstream-bestanden voor Android (rebase-impact)

Alleen de **production**-flavor wordt gebrand; `development` (`nl.jknaapen.fladder.dev`) blijft upstream.

| Bestand | Wijziging |
|---|---|
| `android/app/build.gradle` | production-flavor: `applicationId = "be.thoelen.jtstreaming"` (`// JT-HOOK: android-id`) |
| `android/app/src/main/AndroidManifest.xml` | `android:label="@string/jt_app_name"` (was `Fladder`) |
| `android/app/src/main/res/values/jt_strings.xml` | nieuw: `jt_app_name` = `JT-Streaming` |
| `android/app/src/production/res/mipmap-*/ic_launcher*.png` | JT-icoon: legacy 48 dp, adaptive voorgrond 108 dp (favicon op 72 dp), monochroom (helderheid → dekking) |
| `android/app/src/production/res/drawable-{nodpi,xhdpi,xxhdpi,xxxhdpi}/app_banner.png` | nieuw: TV-banner 320x180 / 480x270 / 640x360 uit `Logo_JT-Streaming.png` (contain, zwarte achtergrond) |
| `android/app/src/production/res/values/colors.xml` | `ic_launcher_background` = `#FF000000` |

Alle beelden en `colors.xml` maakt `tool/jt/generate-icons.ps1` (stap 5); bij een conflict:
`git checkout --ours <bestand>` en het script opnieuw draaien.
Bewust **niet** gewijzigd (rebase-vriendelijk, geen runtime-effect): `namespace` en het Kotlin-package
`nl.jknaapen.fladder` (MainActivity e.a.), de Pigeon-kanaalnamen `nl_jknaapen_fladder.*`, de
notificatiekanaal-id `nl.jknaapen.fladder.channel.playback` en de WorkManager-taaknamen
`nl.jknaapen.fladder.update_notifications_check*` (allemaal per app, botsen niet met Fladder), de
statusbalk-iconen `ic_notification` (upstream-silhouet) en `ic_launcher-playstore.png` (zit niet in de apk).
`${applicationId}`-afhankelijk en dus vanzelf correct: de FileProvider-authority
`be.thoelen.jtstreaming.wallpaper_provider` en `packageName` in `MainActivity`/`WallpaperApiUtility`.
De deep-link-scheme `fladder://` blijft (gedeeld met een eventuele Fladder-installatie: Android vraagt dan
welke app).

## Upstream binnenhalen (rebase)

Remotes:

| Remote | URL | Gebruik |
|---|---|---|
| `upstream` | `https://github.com/DonutWare/Fladder` | alleen fetch; push-URL staat op `DISABLED-no-upstream-push` |
| `origin` | `https://github.com/Xantar-86/JT-Streaming.git` | onze fork; we pushen alleen `jt/main` (en eventuele PR-branches) |

In de fork staan `develop`, `main` en tag `v0.11.1` gelijk aan upstream (tag = `a30343a3`).
Geen force-push op `main`/`develop`, en `v0.11.1` niet wijzigen. Het push-token komt nooit in de
remote-URL: gebruik `git credential` of een eenmalige URL op de opdrachtregel, en controleer
achteraf met `git remote -v`. Na een rebase is een push van `jt/main` een
`git push --force-with-lease origin jt/main` (alleen op die branch).

Onze commits staan bovenop upstream-tag `v0.11.1` op branch `jt/main`:

1. `fix(playback)`, 2. `fix(live-tv)`, 3. `fix(ui)`: upstream-geschikt, geen `lib/jt/`-verwijzingen.
4. `chore(jt)`, 5. `feat(jt): rebrand`, 6. `feat(jt): theme layer`, 7. `feat(jt): defaults`, 8. `build(jt)`.
9. Vanaf jt.3: `chore(jt): vendor media_kit ... unchanged` en `fix(web): ... hls.js` (fix 1d,
   `third_party/media_kit/`, override in `pubspec.yaml`).

```powershell
git fetch upstream --tags
git switch jt/main
git tag jt/backup-<datum>                  # vangnet
git rebase --onto vX.Y.Z v0.11.1 jt/main   # vorige basis -> nieuwe tag
```

Per conflict:
- **Fix-commits (1-3):** heeft upstream de fix overgenomen, laat de commit vallen (`git rebase --skip`).
  Is de code verplaatst, pas de kleine wijziging op de nieuwe plek opnieuw toe.
- **Hook-commits:** upstream wijzigde de regel rond een hook. Neem de upstream-versie en zet de
  `// JT-HOOK`-regel er opnieuw in.
- **Binaire iconen:** `git checkout --ours <bestand>`, daarna `pwsh tool/jt/generate-icons.ps1`.
- **`pubspec.lock`:** wij wijzigen één dependency: `media_kit` is een path-dependency naar
  `third_party/media_kit` (fix 1d). Bij een conflict: `git checkout vX.Y.Z -- pubspec.lock`, daarna
  `flutter pub get` zodat de `media_kit`-regel weer `source: path` wordt.
- **`media_kit` (fix 1d):** pint upstream een andere media-kit-ref (zie `media_kit_video` in
  `pubspec.lock`), volg dan *Bij een upstream-update van media_kit* in `third_party/media_kit/JT-PATCH.md`.

Daarna:

```powershell
git grep -c "JT-HOOK" -- lib ":!lib/jt"   # verwacht: 48 regels in 24 bestanden (stand jt.5, opnemen/DVR)
git grep -c "JT-PATCH" -- third_party ":!*.md"   # verwacht: 9 regels in 2 bestanden (stand jt.3)
flutter analyze
flutter test
pwsh tool/jt/build-web.ps1 -Clean
```

Nieuwe Flutter-versie in `.fvmrc`? Installeer die eerst en zet `$env:JT_FLUTTER_ROOT`.
