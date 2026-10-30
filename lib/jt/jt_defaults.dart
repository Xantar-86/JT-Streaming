import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/util/fladder_config.dart';

/// Standaardinstellingen van JT-Streaming voor nieuwe installaties (en browsers zonder bewaarde
/// instellingen). Wie al instellingen bewaard heeft, behoudt die.
abstract final class JtDefaults {
  static ClientSettingsModel clientSettings(ClientSettingsModel upstream) => upstream.copyWith(
        // Bibliotheeklogo's in de zijbalk (upstream: uit).
        usePosterForLibrary: true,
        // Geen update-melding: die verwijst naar de Fladder-releases van DonutWare (upstream: aan).
        checkForUpdates: false,
      );

  /// Bij elke koude start "Wie kijkt er?" tonen, ook voor profielen met autoLogin (WP3.1).
  static const bool chooseProfileOnStart = true;

  /// Vaste Jellyfin-server (WP3.1): er is geen serverkeuzescherm meer.
  static const String serverUrl = 'https://tv.fam-thoelen.be';

  /// Eigen serveradres van dit toestel ("Profielen beheren > Geavanceerd"), leeg = standaard.
  static const String serverOverrideKey = 'jtServerUrlOverride';

  static String? _deployUrl;
  static bool _applied = false;

  /// Standaard zonder eigen adres: `baseUrl` uit config/config.json (web-deploy) of [serverUrl].
  static String get defaultServer => _deployUrl ?? serverUrl;

  static String? serverOverride(SharedPreferences prefs) {
    final value = prefs.getString(serverOverrideKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Zet [FladderConfig.baseUrl]: eigen adres > deploy-config > [serverUrl].
  static void applyServer(SharedPreferences prefs) {
    if (!_applied) {
      _deployUrl = FladderConfig.baseUrl;
      _applied = true;
    }
    FladderConfig.baseUrl = serverOverride(prefs) ?? defaultServer;
  }

  /// Eigen adres opslaan (`null`/leeg = terug naar standaard) en meteen toepassen.
  static Future<void> setServerOverride(SharedPreferences prefs, String? url) async {
    final value = url?.trim() ?? '';
    if (value.isEmpty || value == defaultServer) {
      await prefs.remove(serverOverrideKey);
    } else {
      await prefs.setString(serverOverrideKey, value);
    }
    applyServer(prefs);
  }
}
