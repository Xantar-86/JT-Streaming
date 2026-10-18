# JT-Streaming aanpassen

JT-Streaming is Fladder (DonutWare, GPL-3.0) met een dunne eigen laag erbovenop.
Vuistregel: **een wijziging aan de interface raakt meestal één bestand: `lib/jt/jt_theme.dart`.**

## Waar staat wat

| Map/bestand | Inhoud |
|---|---|
| `lib/jt/` | Alle eigen code (thema, naam, startscherm, standaardinstellingen) |
| `assets/jt/` | Logo's (© fam. Thoelen, niet onder GPL) |
| `tool/jt/` | Bouw- en icoonscripts |

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
| het logo/icoon | vervang de bronbestanden en hashes, zie `tool/jt/generate-icons.ps1 -SourceDir <map>` |
| de URL van de fork op het Over-scherm | `lib/jt/jt_brand.dart` → `forkUrl` |
| standaardinstellingen voor nieuwe installaties | `lib/jt/jt_defaults.dart` |

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
- Op een Windows-machine zonder symlink-rechten (geen Developer Mode) zet het script de
  desktop-feature-flags van Flutter tijdelijk uit; voor de webbuild zijn die niet nodig.

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
- **`pubspec.lock`:** wij wijzigen geen dependencies. Bij een conflict: `git checkout vX.Y.Z -- pubspec.lock`.

Daarna:

```powershell
git grep -c "JT-HOOK" -- lib ":!lib/jt"   # verwacht: 39 regels in 19 bestanden (stand v0.11.1-jt.1)
flutter analyze
flutter test
pwsh tool/jt/build-web.ps1 -Clean
```

Nieuwe Flutter-versie in `.fvmrc`? Installeer die eerst en zet `$env:JT_FLUTTER_ROOT`.
