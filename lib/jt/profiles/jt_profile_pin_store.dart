import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/shared_provider.dart';

/// Uitkomst van een opvraging bij de server.
sealed class JtPinFetch {
  const JtPinFetch();
}

/// De server antwoordde; [record] is de actuele stand.
class JtPinFetched extends JtPinFetch {
  final JtPinRecord record;
  const JtPinFetched(this.record);
}

/// Het bewaarde token werkt niet meer (401/403): opnieuw inloggen met het wachtwoord.
class JtPinUnauthorized extends JtPinFetch {
  const JtPinUnauthorized();
}

/// Server onbereikbaar. [cached] is de laatst bekende stand op dit toestel (of `null`).
class JtPinOffline extends JtPinFetch {
  final JtPinRecord? cached;
  const JtPinOffline(this.cached);
}

final jtProfilePinStoreProvider = Provider<JtProfilePinStore>((ref) => JtProfilePinStore(ref));

/// Leest en schrijft de pincode-hash van een profiel.
///
/// Bron van waarheid: Jellyfin-DisplayPreferences `jt-streaming` (client `jt-streaming`) van die
/// gebruiker, met het token van het profiel zelf. Op dit toestel blijft enkel een kopie van de hash
/// (voor als de server even weg is) en de teller van foute pogingen.
class JtProfilePinStore {
  JtProfilePinStore(this.ref);

  final Ref ref;

  static const String client = 'jt-streaming';
  static const String preferencesId = 'jt-streaming';
  static const Duration timeout = Duration(seconds: 8);

  static String _cacheKey(AccountModel a) => 'jtPinCache.${a.credentials.serverId}.${a.id}';
  static String _lockKey(AccountModel a) => 'jtPinLock.${a.credentials.serverId}.${a.id}';

  JellyfinOpenApi _api(AccountModel account) =>
      createJellyfinApiForAccount(ref, account.credentials.url, account.credentials.header(ref));

  Future<JtPinFetch> fetch(AccountModel account) async {
    try {
      final response = await _api(account)
          .displayPreferencesDisplayPreferencesIdGet(
            displayPreferencesId: preferencesId,
            userId: account.id,
            $client: client,
          )
          .timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) return const JtPinUnauthorized();
      if (!response.isSuccessful || response.body == null) return JtPinOffline(cached(account));
      final record = JtPinRecord.fromCustomPrefs(response.body!.customPrefs);
      await _cache(account, record);
      return JtPinFetched(record);
    } catch (e) {
      log('JT pin fetch failed: $e');
      return JtPinOffline(cached(account));
    }
  }

  /// Zet ([pin] = 4 cijfers) of verwijdert ([pin] = `null`) de pincode. `true` bij succes.
  Future<bool> save(AccountModel account, String? pin) async {
    final record = pin == null ? JtPinRecord.none : JtPinRecord(JtPin.hash(pin));
    try {
      final api = _api(account);
      final current = await api
          .displayPreferencesDisplayPreferencesIdGet(
            displayPreferencesId: preferencesId,
            userId: account.id,
            $client: client,
          )
          .timeout(timeout);
      if (!current.isSuccessful || current.body == null) return false;
      // Jellyfin wist geen bestaande sleutels; "geen pincode" is dus een lege waarde.
      final prefs = <String, dynamic>{...?current.body!.customPrefs, JtPinRecord.prefsKey: record.hash};
      final response = await api
          .displayPreferencesDisplayPreferencesIdPost(
            displayPreferencesId: preferencesId,
            userId: account.id,
            $client: client,
            body: current.body!.copyWith(id: preferencesId, $Client: client, customPrefs: prefs),
          )
          .timeout(timeout);
      if (!response.isSuccessful) return false;
      await _cache(account, record);
      await resetLockout(account);
      return true;
    } catch (e) {
      log('JT pin save failed: $e');
      return false;
    }
  }

  /// Nieuw token via het Jellyfin-wachtwoord (zelfde DeviceId). Geeft het bijgewerkte profiel terug.
  Future<AccountModel?> reauthenticate(AccountModel account, String password) async {
    try {
      final credentials = account.credentials.copyWith(token: '');
      final response = await createJellyfinApiForAccount(ref, credentials.url, credentials.header(ref))
          .usersAuthenticateByNamePost(body: AuthenticateUserByName(username: account.name, pw: password))
          .timeout(timeout);
      final token = response.body?.accessToken;
      if (!response.isSuccessful || token == null || token.isEmpty) return null;
      if (response.body?.user?.id != null && response.body!.user!.id != account.id) return null;
      final updated = account.copyWith(credentials: account.credentials.copyWith(token: token));
      await ref.read(sharedUtilityProvider).addAccount(updated);
      await resetLockout(account);
      return updated;
    } catch (e) {
      log('JT re-authentication failed: $e');
      return null;
    }
  }

  JtPinRecord? cached(AccountModel account) {
    final raw = ref.read(sharedPreferencesProvider).getString(_cacheKey(account));
    if (raw == null) return null;
    try {
      return JtPinRecord.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cache(AccountModel account, JtPinRecord record) =>
      ref.read(sharedPreferencesProvider).setString(_cacheKey(account), record.toJson());

  JtPinLockout lockout(AccountModel account) =>
      JtPinLockout.fromJson(ref.read(sharedPreferencesProvider).getString(_lockKey(account)));

  Future<void> setLockout(AccountModel account, JtPinLockout value) =>
      ref.read(sharedPreferencesProvider).setString(_lockKey(account), value.toJson());

  Future<void> resetLockout(AccountModel account) => ref.read(sharedPreferencesProvider).remove(_lockKey(account));

  /// Profiel van dit toestel weg: ook de lokale kopie en de teller.
  Future<void> forget(AccountModel account) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_cacheKey(account));
    await prefs.remove(_lockKey(account));
  }
}
