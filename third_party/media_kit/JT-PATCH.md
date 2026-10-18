# media_kit, gevendord met JT-patch (fix 1d)

- **Bron:** `media_kit/` uit https://github.com/DonutWare/media-kit op commit
  `cb56b5a6149f1e51086eba473c7e48041c54ab12` (versie 1.2.2), de ref die upstream-Fladder v0.11.1
  via `ref: main` in `pubspec.lock` pint.
- **Meegenomen:** `lib/`, `assets/`, `pubspec.yaml`, `LICENSE` (MIT, WanJiMi / Hitesh Kumar Saini).
  Niet: `example/`, `test/`, `screenshots/`, README/CHANGELOG.
- **Ongewijzigde kopie:** commit `chore(jt): vendor media_kit 1.2.2 ...`. Alle 51 git-blobs zijn
  gelijk aan upstream (`git ls-tree -r cb56b5a6 media_kit`). De patch staat in de commit erna:
  `git diff <vendor-commit> -- third_party/media_kit`.
- **Inhaken:** `dependency_overrides.media_kit` in `pubspec.yaml` wijst naar `third_party/media_kit`.
  De andere media_kit-pakketten (`media_kit_video`, `media_kit_libs_*`) blijven op de DonutWare-git.
  `analysis_options.yaml` sluit `third_party/**` uit (upstream-code, niet onze lintnorm).

## Wat de patch doet (alleen de weblaag)

Alle regels zijn gemarkeerd met `JT-PATCH (fix 1d)`.

| Bestand | Wijziging |
|---|---|
| `lib/src/player/web/player/real.dart` `_isHLS` | Oud: native HLS zodra `canPlayType('application/vnd.apple.mpegurl') != ''` (behalve Android-Chrome). Chrome op Windows zegt `"maybe"`, en faalt op Jellyfin-streams (zwart beeld, `NotSupportedError`). Nieuw: **bron bevat `m3u8` en `Hls.isSupported()` → altijd hls.js**, ongeacht `canPlayType`. Native alleen als hls.js/MSE ontbreekt (bv. oudere iOS-Safari) of hls.js niet geladen is. |
| `real.dart` `_loadSource` | Logt hls.js-fouten in de console: fatal via `console.error('[jt-hls] fatal', data)`, niet-fatale via `console.debug('[jt-hls] non-fatal', data)` (zichtbaar met "Verbose"). |
| `real.dart` `_loadSource`, `stop`, `dispose`, veld `_hls` | Een vorige hls.js-instantie wordt `destroy()`'d voor een nieuwe bron, bij stop en bij dispose. Upstream liet ze lopen; met hls.js voor elke HLS-bron zou zappen anders oude streams blijven ophalen. |
| `lib/src/player/web/utils/hls.dart` | Interop `Hls.on(event, callback)`, `Hls.destroy()` en constante `kHlsEventError = 'hlsError'`. |

Native codepaden (`lib/src/player/native/**`, libmpv op Windows/Linux/Android) zijn niet gewijzigd.

## Retry bij 503 (segment nog niet klaar)

De patch zet geen hls.js-config behalve `xhrSetup` (upstream). Dus gelden de defaults van de
meegeleverde `assets/web/hls1.4.10.js`:

- `fragLoadPolicy.default.errorRetry`: `maxNumRetry 6`, `retryDelayMs 1000`, `maxRetryDelayMs 8000`
  (`timeoutRetry`: 4x). Een HTTP-status wordt herprobeerd als die `< 400` of `> 499` is, dus 503 wel.
- `playlistLoadPolicy.default.errorRetry`: `maxNumRetry 2`, `retryDelayMs 1000`, `maxRetryDelayMs 8000`.

## Bij een upstream-update van media_kit

1. Kijk welke ref upstream-Fladder in `pubspec.lock` pint (`media_kit_video` blijft een git-dependency
   en laat dat zien).
2. Vervang `lib/`, `assets/`, `pubspec.yaml` en `LICENSE` door die van de nieuwe ref (één commit
   "vendor ... unchanged").
3. Zet de `JT-PATCH (fix 1d)`-regels opnieuw (één commit). Controle: `git grep -c "JT-PATCH" -- third_party ":!*.md"`
   (stand jt.3: 9 regels in 2 bestanden).
4. Neemt upstream media_kit zelf hls.js-voorrang over, verwijder dan deze map en de override.
