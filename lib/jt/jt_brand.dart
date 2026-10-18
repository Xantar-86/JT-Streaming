import 'package:flutter/material.dart';

/// Naam, logo's en bronvermelding van JT-Streaming.
///
/// Alles wat "Fladder" heette in de zichtbare interface loopt via deze klasse
/// (zie de `// JT-HOOK: brand` regels in upstream-bestanden).
abstract final class JtBrand {
  /// Weergavenaam: app, venster, browser, Jellyfin-`Client`-header.
  static const String appName = 'JT-Streaming';

  /// Upstream waarop JT-Streaming gebaseerd is.
  static const String upstreamName = 'Fladder';
  static const String upstreamAuthor = 'DonutWare';
  static const String upstreamUrl = 'https://github.com/DonutWare/Fladder';
  static const String upstreamBase = 'v0.11.1';

  /// Broncode van deze fork. Leeg tot de GitHub-fork bestaat (board-besluit B2).
  static const String forkUrl = '';

  /// Tekst onder de versie in het licentiescherm.
  static const String legalese = 'JT-Streaming, gebaseerd op Fladder © DonutWare, GPL-3.0';

  /// Logo's (© fam. Thoelen, niet onder GPL), kopieën uit `assets/jt/`.
  static const String logoAsset = 'assets/jt/logo.png';
  static const String iconAsset = 'assets/jt/icon.png';

  /// Het app-pictogram, gebruikt waar Fladder zijn eigen icoon toonde.
  static Widget icon(double size) => Image.asset(
        iconAsset,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      );
}
