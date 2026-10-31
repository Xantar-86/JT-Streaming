import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/jt/profiles/jt_manage_profiles.dart';
import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/jt/profiles/jt_profile_pin_store.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';

// Reviewer THEAAA-193: wat gebeurt er als de beheerdialoog sluit terwijl de afmelding nog loopt?
// De gate staat voor een traag/onbereikbaar netwerk (JtProfilePinStore.timeout = 8 s).

final rita = AccountModel(
  name: 'Rita',
  id: 'id-Rita',
  avatar: '',
  lastUsed: DateTime(2026, 10, 30),
  credentials: CredentialsModel.internal(url: 'https://tv.example', serverId: 'srv', token: 't-Rita'),
);

class SlowStore extends JtProfilePinStore {
  SlowStore(super.ref);
  final gate = Completer<void>();
  bool forgotten = false;

  @override
  Future<void> signOut(AccountModel account) => gate.future;
  @override
  Future<void> forget(AccountModel account) async => forgotten = true;
  @override
  JtPinRecord? cached(AccountModel account) => JtPinRecord.none;
}

Future<(ProviderContainer, SlowStore)> openAndRemove(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        jtProfilePinStoreProvider.overrideWith((ref) => SlowStore(ref)),
      ],
      child: MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => AdaptiveLayout(
          data: AdaptiveLayoutModel(
            viewSize: ViewSize.desktop,
            layoutMode: LayoutMode.single,
            inputDevice: InputDevice.pointer,
            platform: TargetPlatform.windows,
            isDesktop: true,
            posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
            controller: {for (final tab in HomeTabs.values) tab: ScrollController()},
            sideBarWidth: 0,
            topBarHeight: 0,
            statusBarHeight: 0,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async {
                await ref.read(sharedUtilityProvider).addAccount(rita);
                ref.read(authProvider.notifier).getSavedAccounts();
                await showJtManageProfiles(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.text('open')));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Verwijderen van dit toestel'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Verwijderen'));
  await tester.pumpAndSettle();
  return (container, container.read(jtProfilePinStoreProvider) as SlowStore);
}

void report(String name, ProviderContainer c, SlowStore s, Object? error) {
  // ignore: avoid_print
  print('RESULT $name: opslag=${c.read(sharedUtilityProvider).getAccounts().map((a) => a.name).toList()} '
      'lijst=${c.read(authProvider).accounts.map((a) => a.name).toList()} forget=${s.forgotten} fout=$error');
}

void main() {
  testWidgets('A controle: dialoog blijft open tijdens de afmelding', (tester) async {
    final (c, s) = await openAndRemove(tester);
    expect(find.text('Rita'), findsOneWidget, reason: 'profiel blijft zichtbaar tot de afmelding klaar is');
    s.gate.complete();
    await tester.pumpAndSettle();
    report('A', c, s, tester.takeException());
    expect(s.forgotten, isTrue);
    expect(c.read(authProvider).accounts, isEmpty);
  });

  testWidgets('B dialoog sluit tijdens de afmelding (terug-toets)', (tester) async {
    final (c, s) = await openAndRemove(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Verwijderen van dit toestel'), findsNothing, reason: 'dialoog moet dicht zijn');
    s.gate.complete();
    await tester.pumpAndSettle();
    report('B', c, s, tester.takeException());
    expect(s.forgotten, isTrue, reason: 'pincode-kopie blijft achter');
    expect(c.read(authProvider).accounts, isEmpty, reason: 'verwijderd profiel staat nog in de lijst');
  });
}
