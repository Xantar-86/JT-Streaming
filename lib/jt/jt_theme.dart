import 'package:flutter/material.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';

/// Rijen van het startscherm, in de volgorde van [JtTheme.homeRows].
enum JtHomeRow {
  banner,
  liveTv,
  continueWatching,
  continueListening,
  continueReading,
  nextUp,
  continueCombined,
  latestPerLibrary,
}

/// HET thema-bestand van JT-Streaming.
///
/// Bijna elke stijlwijziging is één regel hier, gevolgd door een rebuild
/// (`pwsh tool/jt/build-web.ps1`). Zie CUSTOMIZING.md voor voorbeelden.
/// Standaardwaarden zijn gelijk aan upstream Fladder, behalve [accent] en de tegelverhouding van kanalen.
abstract final class JtTheme {
  // ---------------------------------------------------------------- Kleuren

  /// Accentkleur (seed van het kleurenschema, knoppen, focus, accentlijn).
  /// #D88F48 = amber uit Logo_JT-Streaming.png (gemiddelde van de heldere, verzadigde pixels).
  static const Color accent = Color(0xFFD88F48);

  /// `true`: de instelling "systeemkleur" (geen eigen themakleur gekozen) gebruikt [accent]
  /// in plaats van de accentkleur van het besturingssysteem.
  static const bool overrideSystemAccent = true;

  /// `true`: `primary` is exact [accent] in plaats van de door Material 3 afgeleide tint.
  /// Geldt alleen zolang de gebruiker geen eigen themakleur kiest.
  static const bool exactAccent = true;

  /// Kleurvariant van Material 3. `null` = de instelling van de gebruiker (upstream).
  static const DynamicSchemeVariant? schemeVariant = null;

  /// Achtergrond achter zenderlogo's. `null` = `colorScheme.surfaceContainerHigh`.
  static const Color? channelTileBackground = null;

  // ------------------------------------------------------- Vorm en afstand

  /// Hoekradius: kaarten, knoppen, posters (upstream 12).
  static const double radiusSmall = 12;

  /// Hoekradius: dialogen, menu's, lijsten (upstream 16).
  static const double radiusDefault = 16;

  /// Hoekradius: grote vlakken (upstream 32).
  static const double radiusLarge = 32;

  /// Verticale ruimte tussen de rijen van het startscherm (upstream 16).
  static const double rowSpacing = 16;

  /// Binnenmarge rond zenderlogo's in een kanaaltegel.
  static const double channelLogoPadding = 12;

  // ------------------------------------------------------------- Lettertype

  /// Lettertype van de hele app. Ander font: zet de bestanden in assets/jt/fonts/,
  /// declareer de familie in pubspec.yaml onder `fonts:` en vul de naam hier in.
  static const String fontFamily = 'Rubik';

  // ------------------------------------------------------------ Startscherm

  /// Volgorde van de rijen op het startscherm. Een rij weglaten = verbergen.
  /// [JtHomeRow.banner] staat altijd bovenaan; weglaten verbergt hem.
  static const List<JtHomeRow> homeRows = [
    JtHomeRow.banner,
    JtHomeRow.liveTv,
    JtHomeRow.continueWatching,
    JtHomeRow.continueListening,
    JtHomeRow.continueReading,
    JtHomeRow.nextUp,
    JtHomeRow.continueCombined,
    JtHomeRow.latestPerLibrary,
  ];

  /// Alleen deze bibliotheken (naam zoals in Jellyfin) op het startscherm. `null` = volg Jellyfin.
  static const List<String>? homeLibrariesOnly = null;

  /// Deze bibliotheken nooit op het startscherm, bv. `['Eigen muziek']`.
  static const List<String> homeLibrariesHidden = [];

  // ------------------------------------------------------ Tegelverhoudingen

  /// Verhouding (breedte/hoogte, kaart inclusief titelregels) per inhoudstype.
  /// Niet vermeld = upstream-waarde. Kanalen 1.35: het beeld zelf is dan ongeveer 16:9.
  static const Map<FladderItemType, double> tileRatio = {
    FladderItemType.tvchannel: 1.35,
  };

  /// Verhouding van de "Recent toegevoegd"-rij per bibliotheektype. Niet vermeld = upstream.
  static const Map<CollectionType, double> libraryTileRatio = {};

  // ------------------------------------------------------- Aanmeldpagina

  /// Achtergrondbeeld op de aanmeldpagina (server kiezen en inloggen). `false` = upstream.
  static const bool loginBackground = true;

  /// Het beeld. Gemaakt door `tool/jt/generate-icons.ps1` uit `assets/jt/source/Logo_JT-Streaming.png`.
  static const String loginBackgroundAsset = 'assets/jt/login_background.jpg';

  /// Dekking van het beeld boven de achtergrondkleur van het thema (0 = onzichtbaar, 1 = vol).
  static const double loginBackgroundOpacity = 0.35;

  /// Extra laag in de achtergrondkleur van het thema boven het beeld (0 = geen, 0.6 = sterk gedempt).
  static const double loginBackgroundOverlay = 0.0;

  /// Vervaging van het beeld in logische pixels (0 = uit).
  static const double loginBackgroundBlur = 2;

  // --------------------------------------------------------------- Intern

  /// Basisschema van JT-Streaming (gebruikt als geen eigen themakleur gekozen is).
  static ColorScheme defaultScheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness);
    return exactAccent ? scheme.copyWith(primary: accent, onPrimary: _onAccent) : scheme;
  }

  /// Nabewerking van het volledige thema. [source] is het schema waarmee het thema gebouwd werd.
  static ThemeData apply(ThemeData theme, ColorScheme? source) {
    if (!exactAccent || source?.primary != accent) return theme;
    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(primary: accent, onPrimary: _onAccent),
    );
  }

  static Color get _onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black;
}
