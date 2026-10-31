import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/shared_provider.dart';

// Bewust een los bestand zonder testWidgets: dat zou HttpClient vervangen door een nep die altijd 400 geeft.

AccountModel _account(String url) => AccountModel(
      name: 'Rita',
      id: 'id-rita',
      avatar: '',
      lastUsed: DateTime(2026, 10, 31),
      credentials: CredentialsModel.internal(url: url, serverId: 'srv', token: 't-rita'),
    );

Future<ProviderContainer> _container(AccountModel account) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  await container.read(sharedUtilityProvider).addAccount(account);
  return container;
}

void main() {
  test('removeAccount signs the token out on the server and removes the profile', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final logouts = <String>[];
    server.listen((request) {
      if (request.method == 'POST' && request.uri.path == '/Sessions/Logout') {
        logouts.add(request.headers.value('authorization') ?? '');
      }
      request.response.statusCode = 204;
      request.response.close();
    });

    final account = _account('http://127.0.0.1:${server.port}');
    final container = await _container(account);
    await container.read(sharedUtilityProvider).removeAccount(account);

    expect(logouts, hasLength(1));
    expect(logouts.single, contains('t-rita'));
    expect(container.read(sharedUtilityProvider).getAccounts(), isEmpty);
  });

  test('server unreachable: the profile is removed anyway', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();

    final account = _account('http://127.0.0.1:$port');
    final container = await _container(account);
    await container.read(sharedUtilityProvider).removeAccount(account);

    expect(container.read(sharedUtilityProvider).getAccounts(), isEmpty);
  });
}
