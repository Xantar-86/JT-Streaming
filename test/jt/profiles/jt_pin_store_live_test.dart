// Live-proef van de pincode-opslag tegen een echte Jellyfin (WP3.1).
// Draait alleen met JELLYFIN_FORGE_TEST = {"server","username","password"} (testaccount forge-test);
// anders overgeslagen. Laat het account achter zonder pincode. Geheimen worden niet gelogd.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/jt/profiles/jt_profile_pin_store.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/util/application_info.dart';

void main() {
  final raw = Platform.environment['JELLYFIN_FORGE_TEST'];
  final cfg = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;

  test('DisplayPreferences round trip: set, other device, unauthorized, remove', () async {
    final server = (cfg!['server'] as String).replaceAll(RegExp(r'/$'), '');
    final user = cfg['username'] as String;
    final password = cfg['password'] as String;

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      applicationInfoProvider.overrideWith((ref) => ApplicationInfo(
            name: 'JT-Streaming',
            version: '0.11.1',
            buildNumber: '0',
            platform: TargetPlatform.windows,
          )),
    ]);
    addTearDown(container.dispose);
    final store = container.read(jtProfilePinStoreProvider);

    // Gebruikers-id via een gewone login (zelfde als "Profiel toevoegen").
    final auth = await http.post(
      Uri.parse('$server/Users/AuthenticateByName'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'MediaBrowser Client="JT-Streaming", Device="wp3.1-live", DeviceId="wp31-live-a", Version="0.11.1"',
      },
      body: jsonEncode({'Username': user, 'Pw': password}),
    );
    expect(auth.statusCode, 200);
    final body = jsonDecode(auth.body) as Map<String, dynamic>;
    final userId = (body['User'] as Map<String, dynamic>)['Id'] as String;

    AccountModel device(String deviceId, String token) => AccountModel(
          name: user,
          id: userId,
          avatar: '',
          lastUsed: DateTime.now(),
          credentials: CredentialsModel.internal(
            url: server,
            serverId: body['ServerId'] as String,
            deviceId: deviceId,
            token: token,
          ),
        );

    final a = device('wp31-live-a', body['AccessToken'] as String);

    final before = await store.fetch(a);
    debugPrint('fetch before: ${before.runtimeType}');
    expect(before, isA<JtPinFetched>());

    // 1. Toestel A zet 4821.
    expect(await store.save(a, '4821'), isTrue);
    final afterSet = await store.fetch(a);
    expect(afterSet, isA<JtPinFetched>());
    final hash = (afterSet as JtPinFetched).record.hash;
    expect(hash, startsWith('v1\$'));
    expect(hash.contains('4821'), isFalse);
    expect(JtPin.verify('4821', hash), isTrue);
    expect(JtPin.verify('1111', hash), isFalse);

    // 2. Ander toestel (eigen DeviceId, eerste wachtwoord-login) ziet dezelfde code.
    final b0 = device('wp31-live-b', '');
    final b = await store.reauthenticate(b0, password);
    expect(b, isNotNull);
    expect(b!.credentials.token, isNot(a.credentials.token));
    final onB = await store.fetch(b);
    expect(onB, isA<JtPinFetched>());
    expect(JtPin.verify('4821', (onB as JtPinFetched).record.hash), isTrue);

    // 3. Fout wachtwoord -> geen nieuw token.
    expect(await store.reauthenticate(b0, '$password-fout'), isNull);

    // 4. Ongeldig token -> JtPinUnauthorized (dus: opnieuw wachtwoord).
    final broken = device('wp31-live-c', 'ongeldig-token-wp31');
    expect(await store.fetch(broken), isA<JtPinUnauthorized>());

    // 5. Ruwe server-inhoud: alleen de hash, client jt-streaming.
    final rawPrefs = await http.get(
      Uri.parse('$server/DisplayPreferences/jt-streaming?userId=$userId&client=jt-streaming'),
      headers: {
        'authorization':
            'MediaBrowser Client="JT-Streaming", Device="wp3.1-live", DeviceId="wp31-live-a", Version="0.11.1", Token="${a.credentials.token}"',
      },
    );
    expect(rawPrefs.statusCode, 200);
    final dto = jsonDecode(rawPrefs.body) as Map<String, dynamic>;
    final custom = dto['CustomPrefs'] as Map<String, dynamic>;
    debugPrint('server CustomPrefs keys: ${custom.keys.toList()}, Client=${dto['Client']}, '
        'pinHash=${(custom['pinHash'] as String).substring(0, 8)}...');
    expect(custom['pinHash'], hash);

    // 6. Weghalen -> geen pincode meer op beide toestellen.
    expect(await store.save(b, null), isTrue);
    final afterRemove = await store.fetch(a);
    expect((afterRemove as JtPinFetched).record.hasPin, isFalse);

    // Opruimen: tokens van deze proef afmelden.
    for (final t in [a.credentials.token, b.credentials.token]) {
      await http.post(Uri.parse('$server/Sessions/Logout'), headers: {
        'authorization': 'MediaBrowser Client="JT-Streaming", Device="wp3.1-live", DeviceId="x", Version="0.11.1", Token="$t"',
      });
    }
  }, skip: cfg == null ? 'JELLYFIN_FORGE_TEST ontbreekt' : false, timeout: const Timeout(Duration(minutes: 2)));
}
