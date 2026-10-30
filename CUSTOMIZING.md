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

### Gids-navigatie

Code in `lib/jt/guide/` (ontwerp: `docs/ontwerp-gids-navigatie.md` in de projectmap). De gids toont één
**lokale kalenderdag** (00:00-24:00; op de dag van de winteruur-overgang 25 u, in maart 23 u) in plaats van
het vaste venster van upstream (`liveTvProvider`, ongewijzigd: de speler en het startscherm gebruiken het nog).

| Bestand | Inhoud |
|---|---|
| `jt_guide_day.dart` | dag, venster, stap van Eerder/Later, tijdlabels, filter (puur, getest) |
| `jt_guide_cache.dart` | programma's per (dag, zender): batches van max. 20 zenders per GET, max. 3 dagen (LRU), na 60 min opnieuw ophalen met de oude data zichtbaar; EPG-dekking voor de dagkiezer |
| `jt_guide_controller.dart` | getoonde dag en de ene sprongfunctie (Nu, uur, Eerder/Later, dag) |
| `jt_live_tv_guide.dart` | kopie van upstream `LiveTvGuide` met dagvenster en cache-gestuurde rijen |
| `jt_guide_toolbar.dart`, `jt_guide_pickers.dart` | knoppenrij, kopregel, dag- en uurkiezer |
| `jt_guide_keys.dart` | toetsen: pijl voorbij het laatste/eerste programma = volgende/vorige dag; PageUp/PageDown, zender ±, terug-/vooruitspoelen = vorige/volgende dag; `jtGuideArrowShortcuts` zet de pijlen in de gids expliciet op focusverplaatsing (op web zijn het anders scrolltoetsen) |

| Wil je ... | Pas aan |
|---|---|
| de stap van Eerder/Later | `jtGuideStep` in `jt_guide_day.dart` (nu 0,75 × het zichtbare venster, 60-180 min) |
| meer of minder dagen in het geheugen | `JtGuideCache.maxDays` (nu 3) |
| hoe snel de gids opnieuw ophaalt | `JtGuideCache.ttl` (nu 60 min) |
| de zenders per request | `JtGuideCache.batchSize` (nu 20) |
| andere toetsen voor vorige/volgende dag | `jtGuideDayShortcuts` in `jt_guide_keys.dart` |
| de teksten | sleutels `jtGuide…` achteraan in `lib/l10n/app_en.arb` en `app_nl.arb` (daarna `flutter gen-l10n`) |

De dagkiezer biedt de dagen aan van het vroegste tot het laatste programma in de EPG (`/LiveTv/Programs`,
`Limit=1`, oplopend en aflopend); lukt dat niet, dan `/LiveTv/GuideInfo`, anders vandaag t/m vandaag + 6.
Een volledig uitgezonden programma opent een info-dialoog ("Al uitgezonden") zonder "Kijken". Upstream-aanraking:
`live_tv_screen.dart` (`// JT-HOOK: guide-nav`, 2 regels: knoppenrij → `JtGuideToolbar`, `LiveTvGuide` →
`JtLiveTvGuide`) en `channel_row.dart` (3 optionele parameters `timelineEnd`, `programs`, `loading`; generiek,
zonder hook, upstream-geschikt).

### Updates in de browser (service worker)

Flutter registreert in de webversie een service worker (`flutter_service_worker.js`) die
`flutter_bootstrap.js` en `main.dart.js` **cache-first** serveert; alleen `/` gaat eerst naar het netwerk.
Gevolg zonder ingreep: de eerste keer laden na een uitrol draait nog de oude versie (de nieuwe service worker
installeert zich op de achtergrond), en een tabblad dat blijft openstaan, krijgt de nieuwe versie nooit.
Die cache-first-oorzaak geldt voor hosting op `/`. Onder `/fladder/` (productie) serveert de worker die
bestanden niet uit zijn cache; daar komt de oude versie uit de heuristische HTTP-cache van de browser (de
server stuurt geen `Cache-Control`). De fix hieronder werkt voor beide: de nieuwe worker haalt de kernbestanden
op met `cache: 'reload'`, wat ook de HTTP-cache overschrijft (bewijs: `docs/wp2.8c-reviewrapport.md`, E1).
Twee lagen:

1. **Service worker** (nabewerking in `tool/jt/build-web.ps1`, functie `Update-ServiceWorker`; de bron blijft
   Flutters eigen sjabloon). Verschilt de bestandslijst van de nieuwe versie van de vorige, dan begint de nieuwe
   worker bij activatie met een lege cache en herlaadt hij de open tabbladen (`clients.claim()` +
   `client.navigate()`). Bestanden die de worker achteraf ophaalt, worden gevalideerd (`cache: 'no-cache'`).
   De nabewerking zoekt drie vaste stukken tekst in het Flutter-sjabloon; ontbreekt er één (nieuwe
   Flutter-versie), dan stopt de build met een foutmelding: pas dan de ankers in het script aan.
2. **Versiecheck** (`lib/jt/web/jt_update_check.dart`, alleen web): bij het starten en elke 30 min haalt de
   app `jt-buildinfo.json` op (`cache: no-store`). Staat daar een andere `buildId` dan de ingebouwde
   (`--dart-define=JT_BUILD_ID`, door het buildscript gezet), dan toont de app onderaan
   "Nieuwe versie beschikbaar · Herladen". Herladen = de service worker bijwerken (die wist de oude caches
   en herlaadt het tabblad); is er geen nieuwe worker, dan worden de caches gewist, de worker
   uitgeschreven en de pagina herladen. Op Windows en Android doet dit niets. Hook:
   `// JT-HOOK: web-update` in `lib/main.dart` (wrapper in de `builder` van `MaterialApp.router`).
   Testhulp: `localStorage['jt-update-interval-s'] = '10'` verkort het interval (minimum 5 s).

Wie nog een versie van vóór jt.6 open heeft, draait de oude service worker: daar helpt alleen herladen.
Bij het eerste herladen na de uitrol start de oude versie nog één keer; de nieuwe service worker neemt dan
over en herlaadt het tabblad zelf (bewijs: `docs/wp2.8b-verslag.md` in de projectmap).

### Offline-melding (connectivity-guard)

Upstream toont "Offline" na één mislukte aanvraag op `/System/Info/Public` (timeout 2 s) of zodra het
netwerktype niet vpn/ethernet/wifi/mobiel is. Op de Mi Box S (USB-ethernet) gaf dat valse meldingen.
`lib/jt/net/jt_connectivity_guard.dart` beslist nu wanneer de app offline is; alle tijden en de drempel
staan in `JtConnectivityConfig`:

| Instelling | Standaard | Betekenis |
|---|---|---|
| `probeTimeout` | 8 s | timeout per aanvraag op `/System/Info/Public` |
| `failuresBeforeOffline` | 3 | mislukte probes na elkaar voor "Offline" |
| `retryDelay` | 5 s | wachttijd tussen die probes (status blijft intussen staan) |
| `noneDebounce` | 3 s | na "geen netwerk": wachten, opnieuw lezen en proben |
| `offlineReprobe` | 30 s | achtergrondprobe zolang de app offline is |

Netwerktype `other` (USB-ethernet, onbekende adapter) telt als vaste verbinding. Hooks:
`// JT-HOOK: connectivity-guard` in `lib/providers/connectivity_provider.dart` (2 regels).
Tests: `test/jt/jt_connectivity_guard_test.dart`.

### Profielen, pincode en vaste server (WP3.1)

Bij elke koude start toont de app "Wie kijkt er?" (`lib/jt/profiles/jt_profiles_screen.dart`): de profielen
die op dit toestel al eens ingelogd zijn, "Profiel toevoegen" en "Profielen beheren". "Wissel van profiel"
staat in de zijbalk en de lade onder de gebruikersavatar.

| Wat | Waar |
|---|---|
| Vaste server (standaard `https://tv.fam-thoelen.be`) | `JtDefaults.serverUrl` in `lib/jt/jt_defaults.dart`. Volgorde: eigen adres van het toestel ("Profielen beheren > Geavanceerd") > `baseUrl` uit `config/config.json` (web-deploy) > `serverUrl` |
| Ook met autoLogin altijd "Wie kijkt er?" | `JtDefaults.chooseProfileOnStart` (`false` = upstream: meteen het laatste account) |
| Profielscherm uit (upstream-raster terug) | `jtProfilesEnabled` in `jt_profiles_screen.dart` |
| Nooit getoonde profielen | `jtHiddenProfiles` in `lib/jt/profiles/jt_profile_flow.dart` (nu `forge-test`) |
| Pincode: lengte, iteraties, 5 fouten / 30 s | `JtPin` en `JtPinLockout` in `lib/jt/profiles/jt_pin.dart` |

De pincode zelf wordt nergens bewaard. Op de server staat in de DisplayPreferences van de gebruiker
(id en client `jt-streaming`, sleutel `pinHash`) een gezouten PBKDF2-HMAC-SHA256-hash
`v1$<iteraties>$<zout>$<hash>`; lege waarde = geen pincode (Jellyfin wist geen sleutels). Elk toestel leest
die met het token van het profiel zelf, dus dezelfde code geldt overal. Lokaal blijven alleen een kopie
van de hash (voor als de server even weg is) en de teller van foute pogingen. Pincode of wachtwoord vergeten:
"Pincode vergeten?" logt opnieuw in met het Jellyfin-wachtwoord (nieuw token, zelfde toestel-id).
Let op: 4 cijfers zijn 10 000 mogelijkheden; wie de DisplayPreferences kan lezen (de gebruiker zelf,
Jellyfin-beheerders) kan de code terugrekenen. Het is een gezinsslot, geen beveiliging van het account.

De app vraagt nooit de gebruikerslijst op (`/Users/Public`); de server wordt pas aangesproken bij het
kiezen of toevoegen van een profiel. Hooks: `// JT-HOOK: profiles` in `auth_provider.dart` (4),
`splash_screen.dart`, `login_screen.dart` (2), `app_bootstrap.dart`, `side_navigation_bar.dart`,
`navigation_drawer.dart`. Tests: `test/jt/profiles/` (de live-proef draait alleen met
`JELLYFIN_FORGE_TEST`).

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
  `jt-streaming-web-<versie>.tar` en `.tar.sha256`. Versie = `0.11.1-jt.<BuildNumber>`, of `0.11.1-jt.<JtVersion>` met
  `-JtVersion 5.2` (tussenversies; zelfde regel als `build-android.ps1`, bv. `-BuildNumber 5002`).
- Bouw ná het taggen: `BUILDINFO.txt`/`jt-buildinfo.json` tonen dan `source=<tag>`.
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

- Zelfde Flutter-, lockfile- en icoonregels als de webbuild; versie = `0.11.1-jt.<BuildNumber>` (of `-jt.<JtVersion>` met `-JtVersion`).
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
| `windows/runner/flutter_window.cpp` | include + 1 regel `JtInstallAccessibilityGate(...)` na `SetChildContent` (`// JT: WP2.11`) |
| `windows/runner/CMakeLists.txt` | bron `jt_accessibility_gate.cpp` + `comctl32.lib` (`# JT: WP2.11`) |

Bij een conflict in deze bestanden: neem de upstream-versie en zet onze regel(s) er opnieuw in.
Niet gewijzigd: de mpv-venstertitel `nl.jknaapen.fladder` in `lib/wrappers/players/lib_mpv.dart`
(intern, niet zichtbaar) en de Flatpak-id's.

Eigen bestanden (geen conflict bij rebase): `windows/runner/jt_accessibility_gate.{h,cpp}`.

#### Toegankelijkheid op Windows (blijvende patch, WP2.11)

Crash jt.6.1 (22/10/2026, `flutter_windows.dll` 0xc0000005): de Flutter-engine zet de
toegankelijkheidsboom (semantics) aan zodra *een* programma de app via MSAA/UI Automation bevraagt, en
crasht daarna soms in `AccessibilityBridge::CreateRemoveReparentedNodesUpdate` als de boom snel
verandert (bv. bladeren in de muziekbibliotheek). Upstream: flutter/flutter#175041, nog geen fix.
De runner-poort `jt_accessibility_gate` laat die verzoeken alleen door naar Flutter als een
schermlezer actief is (`SPI_GETSCREENREADER`, of Verteller: `HKCU\Software\Microsoft\Narrator\NoRoam\RunningState`),
of als de omgevingsvariabele `JT_ACCESSIBILITY=1` gezet is. Andere programma's krijgen het
standaardantwoord van Windows; de semantics blijven dan uit.
Bij een rebase/Flutter-update: patch behouden tot upstream #175041 aantoonbaar opgelost is
(controleer `CreateRemoveReparentedNodesUpdate` in `shell/platform/common/accessibility_bridge.cc`:
null-parent- en `iter == end`-controle). Pas dan mag hij weg.

Gevolg (aanvaard door de board op 23/10/2026; Jochen gebruikt geen schermlezer of spraakbediening):
programma's die de app via UI Automation lezen maar geen schermlezer zijn, zoals Spraaktoegang
(Voice Access), Inspect/Accessibility Insights of UIA-testtools, zien in JT-Streaming alleen het
lege venster en niet de knoppen of teksten.

**Poort weer uitzetten:**
- *Zonder herbouw, per gebruiker:* zet `JT_ACCESSIBILITY=1` (PowerShell:
  `[Environment]::SetEnvironmentVariable('JT_ACCESSIBILITY','1','User')`), meld af en weer aan
  (of herstart Verkenner) en start de app opnieuw. Flutter krijgt dan elk MSAA/UIA-verzoek, zoals
  zonder de patch. Terugdraaien: dezelfde opdracht met `$null` als waarde.
- *Blijvend, in de code:* verwijder in `windows/runner/flutter_window.cpp` de include en de regel
  `JtInstallAccessibilityGate(...)` (`// JT: WP2.11`), haal in `windows/runner/CMakeLists.txt`
  `jt_accessibility_gate.cpp` en `comctl32.lib` weg (`# JT: WP2.11`), verwijder
  `windows/runner/jt_accessibility_gate.{h,cpp}` en herbouw met `build-windows.ps1 -Clean`.
  Let op: daarmee komt de crash van jt.6.1 terug zolang upstream #175041 niet opgelost is.

### Android TV-app (apk)

```powershell
pwsh tool/jt/build-android.ps1 -Clean -JtVersion 5.1 -OutDir C:\paperclip\forge\projects\jt-streaming\dist-android
```

- Zelfde Flutter-, lockfile- en icoonregels als de webbuild. Versie = `0.11.1-jt.<JtVersion>`,
  build-number = 1000 × jt-nummer + subnummer (`jt.5.1` = 5001, `jt.6.6` = 6006; of `-VersionCode N`).
- **Eén apk per ABI** (sinds jt.6.6; `--split-per-abi --target-platform android-arm,android-arm64`):
  `JT-Streaming-AndroidTV-<versie>-armeabi-v7a.apk` (Xiaomi Mi Box S: Android 9, 32-bit userland) en
  `JT-Streaming-AndroidTV-<versie>-arm64-v8a.apk` (Google TV Streamer en andere 64-bit toestellen).
  Welke een toestel nodig heeft: `adb shell getprop ro.product.cpu.abilist` (eerste waarde). Een arm64-apk
  op een 32-bit box geeft "App niet geïnstalleerd". x86_64 (alleen de emulator) zit er niet meer bij.
  **versionCode = 10 × build-number + 1 (armeabi-v7a) of + 2 (arm64-v8a)** (`jt.6.6` = 60061 / 60062),
  gezet door `// JT-HOOK: abi-version-code` in `android/app/build.gradle`. Android installeert een update
  alleen over de bestaande app als de versionCode hoger is én dezelfde sleutel signeert; een ABI-apk ligt
  dus boven elke universele apk t/m jt.6.5 (6005). Ga daarna niet terug naar een universele apk (lager getal).
- `-Universal`: de oude universele apk (`armeabi-v7a`, `arm64-v8a`, `x86_64`, ~222 MB, versionCode =
  build-number), bv. voor de emulator.
- Uitvoer: `build/app/outputs/flutter-apk/app-<abi>-production-release.apk`, gekopieerd naar `<OutDir>`
  + `.sha256` per apk (standaard `dist/`). Exitcode ≠ 0 bij elke fout.
- Native libraries staan ongecomprimeerd in de apk (AGP-standaard, `extractNativeLibs` niet gezet):
  Android gebruikt ze rechtstreeks uit de apk, dus geïnstalleerd ≈ apk-grootte. `useLegacyPackaging`
  zou de download kleiner maken maar de libs bij installatie uitpakken: meer plaats op de box, niet minder.
- `pubspec.yaml` neemt van de map `assets/` alleen `gradient.png` mee (`# JT-HOOK: asset-trim`); de
  Affinity-bronbestanden (`*.afphoto`, `*.afdesign`, 3,5 MB) zitten niet meer in apk, web en Windows.
- **Signering**: release-keystore (RSA 4096, alias `jtstreaming`) als JSON
  `{storeBase64, storePassword, keyAlias, keyPassword}` uit `$env:JT_STREAMING_ANDROID_KEYSTORE`
  (company-secret `jt_streaming_android_keystore`), anders uit het bestand in
  `$env:JT_STREAMING_ANDROID_KEYSTORE_FILE` (standaard
  `C:\paperclip\forge\secrets\jt-streaming\jt_streaming_android_keystore.json`, buiten de repo, ACL alleen
  de bouwgebruiker). Het script schrijft `android/app/key.properties` + `keystore.jks` (gitignored, het
  controleert dat) en wist ze na de bouw, ook bij een fout. Daarna controleert het met `apksigner` dat het
  certificaat exact dat van de keystore is (nooit de debug-sleutel) en met `aapt2 dump badging` package,
  label, versie, versionCode, leanback-launcher, banner, icoon, ABI's (per apk precies één) en "niet debuggable".
  **Verlies de keystore niet**: zonder dezelfde sleutel kan een update niet over de bestaande app heen
  (eerst verwijderen = lokale app-instellingen kwijt).
- Vereist op de bouwmachine (alles per gebruiker, geen admin): **JDK 17** (`$env:JAVA_HOME`, standaard
  `C:\paperclip\tools\jdk-17.0.20.1+1`, Temurin-zip) en de **Android SDK** (`$env:ANDROID_HOME`, standaard
  `C:\paperclip\tools\android-sdk`) met `platform-tools`, `build-tools;36.0.0` (+ `35.0.0`, die AGP zelf
  vraagt), `platforms;android-37.0` (compileSdk 37), `platforms;android-36` en `ndk;27.0.12077973` (de
  NDK-versie van Flutter 3.35.7).
  **Installeer ze met cmdline-tools 19.0** (`<sdk>\cmdline-tools\19.0\bin\sdkmanager.bat --install ...`),
  niet met de nieuwste (23.0): die schrijft `package.xml` in SDK-XML-versie 4, die AGP 8.12 negeert
  ("only understands SDK XML versions up to 3"), met als gevolg
  `Failed to find target with hash string 'android-37'`.
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
| `origin` | `https://github.com/Xantar-86/JT-Streaming.git` | onze fork; we pushen alleen `jt/main` (de oude `upstream/*-v2`-branches blijven staan als referentie) |

In de fork staan `develop`, `main` en tag `v0.11.1` gelijk aan upstream (tag = `a30343a3`).
Geen force-push op `main`/`develop`, en `v0.11.1` niet wijzigen. Het push-token komt nooit in de
remote-URL: gebruik `git credential` of een eenmalige URL op de opdrachtregel, en controleer
achteraf met `git remote -v`. Na een rebase is een push van `jt/main` een
`git push --force-with-lease origin jt/main` (alleen op die branch).

**Onze patches blijven altijd mee.** Besluit van de board (22/10/2026): JT-Streaming dient geen
pull requests in bij DonutWare/Fladder of media-kit. Onze fixes en de vendor-patch op `media_kit`
zitten dus alleen in deze fork en moeten bij elke rebase opnieuw mee. De branches
`upstream/fix-live-tv-stream-url-v2` en `upstream/fix-channel-logo-aspect-v2` (fork JT-Streaming) en
`fix-web-hls-prefer-hlsjs` (media-kit, alleen lokaal) zijn alleen nog referentie; niet indienen, niet bijwerken.

Onze commits staan bovenop upstream-tag `v0.11.1` op branch `jt/main`:

1. `fix(playback)`, 2. `fix(live-tv)`, 3. `fix(ui)`: los van `lib/jt/` gehouden, zodat ze klein blijven bij een rebase.
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
- **Fix-commits (1-3) en fix 1d:** standaard altijd behouden. Is de code verplaatst, pas de kleine
  wijziging op de nieuwe plek opnieuw toe. Alleen als upstream zelf aantoonbaar hetzelfde probleem
  heeft opgelost (live tv speelt, logo's niet bijgesneden, web-HLS via hls.js), mag de commit
  vallen (`git rebase --skip`); test dat dan eerst op de nieuwe upstream-versie.
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
git grep -c "JT-HOOK" -- lib ":!lib/jt"   # verwacht: 66 regels in 31 bestanden (stand jt.6.7: + profiles)
git grep -c "JT-PATCH" -- third_party ":!*.md"   # verwacht: 9 regels in 2 bestanden (stand jt.3)
flutter analyze
flutter test
pwsh tool/jt/build-web.ps1 -Clean
```

Nieuwe Flutter-versie in `.fvmrc`? Installeer die eerst en zet `$env:JT_FLUTTER_ROOT`.
