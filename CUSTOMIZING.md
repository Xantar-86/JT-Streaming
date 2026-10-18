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

_(wordt aangevuld in de build-commit)_

## Upstream binnenhalen (rebase)

_(wordt aangevuld in de build-commit)_
