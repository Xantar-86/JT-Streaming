import 'package:fladder/models/settings/client_settings_model.dart';

/// Standaardinstellingen van JT-Streaming voor nieuwe installaties (en browsers zonder bewaarde
/// instellingen). Wie al instellingen bewaard heeft, behoudt die.
abstract final class JtDefaults {
  static ClientSettingsModel clientSettings(ClientSettingsModel upstream) => upstream.copyWith(
        // Bibliotheeklogo's in de zijbalk (upstream: uit).
        usePosterForLibrary: true,
        // Geen update-melding: die verwijst naar de Fladder-releases van DonutWare (upstream: aan).
        checkForUpdates: false,
      );
}
