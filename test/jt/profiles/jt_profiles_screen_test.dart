import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/jt/profiles/jt_manage_profiles.dart';
import 'package:fladder/jt/profiles/jt_pin.dart';
import 'package:fladder/jt/profiles/jt_pin_pad.dart';
import 'package:fladder/jt/profiles/jt_profile_flow.dart';
import 'package:fladder/jt/profiles/jt_profile_pin_store.dart';
import 'package:fladder/jt/profiles/jt_profile_widgets.dart';
import 'package:fladder/jt/profiles/jt_profiles_screen.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';

AccountModel _account(String name, {int minutesAgo = 60}) => AccountModel(
      name: name,
      id: 'id-$name',
      avatar: '',
      lastUsed: DateTime(2026, 10, 30, 20).subtract(Duration(minutes: minutesAgo)),
      credentials: CredentialsModel.internal(url: 'https://tv.example', serverId: 'srv', token: 't-$name'),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1920, 1080),
  List<Override> overrides = const [],
  Map<ShortcutActivator, Intent>? shortcuts,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), ...overrides],
      child: MaterialApp(
        locale: const Locale('nl'),
        shortcuts: shortcuts,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // FladderSnack vraagt de maat op bij AdaptiveLayout.
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
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _focusedTileKey() {
  String? key;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    final k = element.widget.key;
    if (k is ValueKey<String> && k.value.startsWith('jt-profile')) {
      key = k.value;
      return false;
    }
    return true;
  });
  return key;
}

/// Op web zijn pijltoetsen standaard scrollen (zie WP2.8d): zonder deze kaart test de VM dat niet.
const Map<ShortcutActivator, Intent> _webArrows = {
  SingleActivator(LogicalKeyboardKey.arrowLeft): ScrollIntent(direction: AxisDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight): ScrollIntent(direction: AxisDirection.right),
  SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
};

class _FakePinStore extends JtProfilePinStore {
  _FakePinStore(super.ref, this.record);

  JtPinRecord record;
  bool serverUp = true;
  bool hasCopy = true;

  @override
  Future<JtPinFetch> fetch(AccountModel account) async =>
      serverUp ? JtPinFetched(record) : JtPinOffline(cached(account));

  @override
  JtPinRecord? cached(AccountModel account) => hasCopy ? record : null;

  @override
  Future<bool> save(AccountModel account, String? pin) async {
    if (!serverUp) return false;
    record = pin == null ? JtPinRecord.none : JtPinRecord(JtPin.hash(pin));
    return true;
  }

  @override
  Future<AccountModel?> reauthenticate(AccountModel account, String password) async =>
      password == 'juist' ? account : null;
}

Override _pinStore(JtPinRecord record) => jtProfilePinStoreProvider.overrideWith((ref) => _FakePinStore(ref, record));

Future<void> _open(WidgetTester tester, Future<void> Function(BuildContext context, WidgetRef ref) action,
    {List<Override> overrides = const [],
    Map<ShortcutActivator, Intent>? shortcuts,
    Size size = const Size(1920, 1080)}) async {
  await _pump(
    tester,
    Consumer(
      builder: (context, ref, _) => TextButton(onPressed: () => action(context, ref), child: const Text('open')),
    ),
    overrides: overrides,
    shortcuts: shortcuts,
    size: size,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _letSnackExpire(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 30));
  await tester.pumpAndSettle();
}

bool _fieldHasFocus(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasPrimaryFocus;

Color _ringColor(WidgetTester tester, Finder label) {
  final ring = find.ancestor(of: label, matching: find.byType(JtFocusRing));
  final box = tester.widget<AnimatedContainer>(find.descendant(of: ring, matching: find.byType(AnimatedContainer)).first);
  return (box.decoration! as BoxDecoration).border!.top.color;
}

void main() {
  group('Dialogen met de afstandsbediening', () {
    testWidgets('remove confirmation: arrow right reaches "Verwijderen", also with the web arrow keys', (tester) async {
      await _open(
        tester,
        (context, ref) => jtRemoveProfile(context, ref, _account('Rita')),
        shortcuts: _webArrows,
      );
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FilledButton>(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FilledButton>(), isNotNull);
    });

    testWidgets('wrong password: focus returns to the field', (tester) async {
      await _open(
        tester,
        (context, ref) => jtAskPassword(context, ref, _account('Lotte')),
        overrides: [_pinStore(JtPinRecord.none)],
      );
      await tester.enterText(find.byType(TextField), 'fout');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(_fieldHasFocus(tester), isTrue);
    });

    for (final (name, value) in const [('invalid', 'tv.example'), ('valid', 'https://tv.example')]) {
      testWidgets('Enter in the server address ($name): focus stays in the field', (tester) async {
        await _open(tester, (context, ref) => showJtManageProfiles(context));
        await tester.tap(find.text('Geavanceerd'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), value);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(_fieldHasFocus(tester), isTrue);
        await _letSnackExpire(tester);
      });
    }

    testWidgets('after "Pincode weghalen" no stale focus ring on the remove button', (tester) async {
      await _open(tester, (context, ref) async {
        await ref.read(sharedUtilityProvider).addAccount(_account('Mila'));
        ref.read(authProvider.notifier).getSavedAccounts();
        await showJtManageProfiles(context);
      }, overrides: [_pinStore(JtPinRecord(JtPin.hash('2580')))]);
      final remove = find.text('Pincode weghalen');
      expect(remove, findsOneWidget);
      // Geen pijl naar de knop: het testlettertype is breed en de rij breekt anders af dan op een echt scherm.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      Focus.of(tester.element(remove)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      for (final k in [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit0,
      ]) {
        await tester.sendKeyEvent(k);
      }
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      expect(_ringColor(tester, find.text('Verwijderen van dit toestel')), Colors.transparent);
      await _letSnackExpire(tester);
    });
  });

  group('Wie kijkt er?', () {
    final accounts = [
      _account('Jochen', minutesAgo: 90),
      _account('forge-test', minutesAgo: 1),
      _account('Lotte', minutesAgo: 10),
      _account('Mila', minutesAgo: 300),
    ];

    testWidgets('title, profiles, add tile, manage button; forge-test never shown', (tester) async {
      await _pump(tester, JtProfilesScreen(accounts: accounts));
      expect(find.text('Wie kijkt er?'), findsOneWidget);
      expect(find.text('Jochen'), findsOneWidget);
      expect(find.text('Lotte'), findsOneWidget);
      expect(find.text('Mila'), findsOneWidget);
      expect(find.text('forge-test'), findsNothing);
      expect(find.text('Profiel toevoegen'), findsOneWidget);
      expect(find.text('Profielen beheren'), findsOneWidget);
      // Zonder foto: cirkel met de beginletter.
      expect(find.text('J'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('focus starts on the last used visible profile (Lotte, not forge-test)', (tester) async {
      await _pump(tester, JtProfilesScreen(accounts: accounts));
      expect(_focusedTileKey(), 'jt-profile-srv-id-Lotte');
    });

    testWidgets('D-pad: arrows move the focus between tiles', (tester) async {
      await _pump(tester, JtProfilesScreen(accounts: accounts));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedTileKey(), 'jt-profile-srv-id-Mila');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedTileKey(), 'jt-profile-add');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_focusedTileKey(), 'jt-profile-srv-id-Jochen');
    });

    testWidgets('start-up order (first empty, then the saved accounts): focus moves to the last used',
        (tester) async {
      final list = ValueNotifier<List<AccountModel>>([]);
      await _pump(
        tester,
        ValueListenableBuilder<List<AccountModel>>(
          valueListenable: list,
          builder: (_, value, __) => JtProfilesScreen(accounts: value),
        ),
      );
      expect(_focusedTileKey(), 'jt-profile-add');
      list.value = accounts;
      await tester.pumpAndSettle();
      expect(_focusedTileKey(), 'jt-profile-srv-id-Lotte');
    });

    testWidgets('no profiles yet: focus on "Profiel toevoegen"', (tester) async {
      await _pump(tester, JtProfilesScreen(accounts: [_account('forge-test')]));
      expect(_focusedTileKey(), 'jt-profile-add');
    });

    for (final size in const [Size(1920, 1080), Size(960, 540), Size(1280, 800), Size(380, 760)]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await _pump(tester, JtProfilesScreen(accounts: accounts), size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('Wie kijkt er?'), findsOneWidget);
      });
    }

    test('jtVisibleProfiles hides forge-test case-insensitively', () {
      final visible = jtVisibleProfiles([_account('Forge-Test'), _account('Jochen')]);
      expect(visible.map((a) => a.name), ['Jochen']);
    });
  });

  group('Pincodeblok', () {
    Future<JtPinPadOutcome?> open(
      WidgetTester tester, {
      JtPinCheck? check,
      DateTime? Function()? lockedUntil,
      Size size = const Size(1920, 1080),
    }) async {
      JtPinPadOutcome? outcome;
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => outcome = await showJtPinPad(
              context,
              title: 'Pincode van Lotte',
              header: const SizedBox.square(dimension: 72), // zoals JtProfileAvatar in jt_profile_flow
              check: check,
              lockedUntil: lockedUntil,
              showForgot: true,
            ),
            child: const Text('open'),
          ),
        ),
        size: size,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return outcome;
    }

    testWidgets('digit keys of remote/keyboard (incl. numpad) enter the code', (tester) async {
      final tried = <String>[];
      await open(tester, check: (pin) async {
        tried.add(pin);
        return null;
      });
      expect(find.text('Pincode van Lotte'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad8);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(tried, ['4821']);
      expect(find.text('Pincode van Lotte'), findsNothing);
    });

    testWidgets('D-pad on the on-screen keypad: focus starts on 1, select presses it', (tester) async {
      final tried = <String>[];
      await open(tester, check: (pin) async {
        tried.add(pin);
        return null;
      });
      // 1 (focus) -> rechts 2 -> rechts 3 -> omlaag 6
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tried, ['1236']);
    });

    testWidgets('wrong code shows the message and clears; locked shows countdown and ignores digits',
        (tester) async {
      DateTime? until;
      var calls = 0;
      await open(
        tester,
        lockedUntil: () => until,
        check: (pin) async {
          calls++;
          until = DateTime.now().add(const Duration(seconds: 30));
          return 'Foute pincode';
        },
      );
      for (final k in [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit1]) {
        await tester.sendKeyEvent(k);
      }
      await tester.pump();
      expect(calls, 1);
      expect(find.textContaining('Te veel foute pogingen'), findsOneWidget);
      for (final k in [LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit2]) {
        await tester.sendKeyEvent(k);
      }
      await tester.pump();
      expect(calls, 1, reason: 'no attempts during the 30 s lock');
      until = null;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    });

    testWidgets('"Pincode vergeten?" returns forgot', (tester) async {
      JtPinPadOutcome? outcome;
      SharedPreferences.setMockInitialValues({});
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => outcome = await showJtPinPad(context, title: 'x', showForgot: true),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pincode vergeten?'));
      await tester.pumpAndSettle();
      expect(outcome?.forgot, isTrue);
      expect(outcome?.pin, isNull);
    });

    for (final size in const [Size(960, 540), Size(1280, 800), Size(1920, 1080), Size(400, 820)]) {
      testWidgets('every key and "vergeten" fully on screen at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await open(tester, size: size);
        expect(tester.takeException(), isNull);
        final screen = Offset.zero & size;
        for (final label in ['1', '3', '0', '9']) {
          final rect = tester.getRect(find.text(label));
          expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue, reason: '$label $rect');
        }
        final forgot = tester.getRect(find.textContaining('Pincode vergeten?'));
        expect(forgot.bottom <= size.height && forgot.top >= 0, isTrue, reason: '$forgot');
        final backspace = tester.getRect(find.bySemanticsLabel('Wissen'));
        expect(backspace.bottom <= size.height, isTrue, reason: '$backspace');
      });
    }
  });

  group('Mi Box-test jt.6.7', () {
    Future<void> enter(WidgetTester tester, String pin) async {
      for (final digit in pin.split('')) {
        await tester.sendKeyEvent(LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(digit)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    AccountModel localLock(String name) => _account(name).copyWith(authMethod: Authentication.passcode, localPin: '1234');

    testWidgets('fout 1: an old upstream lock gets our pad, 5 wrong codes = 30 s wait', (tester) async {
      await _open(
        tester,
        (context, ref) => jtEnterProfile(context, ref, localLock('Jochen')),
        overrides: [_pinStore(JtPinRecord.none)],
      );
      expect(find.byType(JtPinPadDialog), findsOneWidget);
      for (var attempt = 1; attempt <= 4; attempt++) {
        await enter(tester, '0000');
        expect(find.text('Foute pincode, nog ${5 - attempt} pogingen'), findsOneWidget);
      }
      await enter(tester, '0000');
      expect(find.textContaining('Te veel foute pogingen'), findsOneWidget);
      await enter(tester, '1234');
      expect(find.byType(JtPinPadDialog), findsOneWidget, reason: 'locked: even the right code is refused');
    });

    testWidgets('fout 2: "vergeten" is reachable with the D-pad before any mistake', (tester) async {
      await _open(
        tester,
        (context, ref) => jtEnterProfile(context, ref, _account('Lotte')),
        overrides: [_pinStore(JtPinRecord(JtPin.hash('1234')))],
        size: const Size(960, 540),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>(), isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget, reason: 'password dialog');
    });

    testWidgets('eis 5: the offer starts on "Pincode instellen", arrow left + Enter skips', (tester) async {
      await _open(
        tester,
        (context, ref) => jtOfferPin(context, ref, _account('Mila')),
        overrides: [_pinStore(JtPinRecord.none)],
      );
      expect(find.text('Pincode instellen voor Mila?'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FilledButton>(), isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Pincode instellen voor Mila?'), findsNothing);
      expect(find.byType(JtPinPadDialog), findsNothing);
    });

    testWidgets('eis 5: "Pincode instellen" saves the code after entering it twice', (tester) async {
      final record = _pinStore(JtPinRecord.none);
      late JtProfilePinStore store;
      await _open(tester, (context, ref) {
        store = ref.read(jtProfilePinStoreProvider);
        return jtOfferPin(context, ref, _account('Mila'));
      }, overrides: [record]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await enter(tester, '2580');
      await tester.pumpAndSettle();
      await enter(tester, '2580');
      await tester.pumpAndSettle();
      expect(JtPin.verify('2580', (store as _FakePinStore).record.hash), isTrue);
      await _letSnackExpire(tester);
    });

    for (final (name, label, stored, asked) in [
      ('without a PIN', 'Mila', JtPinRecord.none, true),
      ('with a PIN', 'Lotte', JtPinRecord(JtPin.hash('1234')), false),
      ('forge-test', 'forge-test', JtPinRecord.none, false),
    ]) {
      testWidgets('eis 5: after login, profile $name: asked = $asked', (tester) async {
        await _open(tester, (context, ref) async {
          ref.read(userProvider.notifier).userState = _account(label);
          await jtOfferPinAfterLogin(context, ref);
        }, overrides: [_pinStore(stored)]);
        expect(find.textContaining('Pincode instellen voor'), asked ? findsOneWidget : findsNothing);
      });
    }
  });

  group('Nacontrole jt.6.8, B7: oud slot in Profielen beheren', () {
    final locked = _account('Jochen').copyWith(authMethod: Authentication.passcode, localPin: '4321');
    late SharedHelper shared;
    late _FakePinStore store;

    Future<void> digits(WidgetTester tester, String pin) async {
      for (final digit in pin.split('')) {
        await tester.sendKeyEvent(LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(digit)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    Future<void> start(WidgetTester tester, Future<void> Function(BuildContext, WidgetRef, AccountModel) action) =>
        _open(tester, (context, ref) async {
          shared = ref.read(sharedUtilityProvider);
          store = ref.read(jtProfilePinStoreProvider) as _FakePinStore;
          await shared.saveAccounts([locked]);
          await action(context, ref, locked);
        }, overrides: [_pinStore(JtPinRecord.none)]);

    void expectStillLocked() {
      final saved = shared.getAccounts().single;
      expect(saved.authMethod, Authentication.passcode);
      expect(saved.localPin, '4321');
      expect(store.record.hasPin, isFalse);
    }

    void expectMovedTo(String pin) {
      final saved = shared.getAccounts().single;
      expect(saved.authMethod, Authentication.autoLogin);
      expect(saved.localPin, isEmpty);
      expect(saved.lastUsed, locked.lastUsed, reason: 'the focus starts on the last used profile: not changed by this');
      expect(JtPin.verify(pin, store.record.hash), isTrue);
    }

    testWidgets('set: without the old code there is no new code', (tester) async {
      await start(tester, jtSetPin);
      expect(find.text('Voer de huidige pincode in'), findsOneWidget);
      await digits(tester, '9999');
      expect(find.text('Foute pincode, nog 4 pogingen'), findsOneWidget);
      expect(find.text('Kies een pincode van 4 cijfers'), findsNothing);
      expectStillLocked();
    });

    testWidgets('set: the right old code moves the lock to the new code', (tester) async {
      await start(tester, jtSetPin);
      await digits(tester, '4321');
      await digits(tester, '9999');
      await digits(tester, '9999');
      expectMovedTo('9999');
      await _letSnackExpire(tester);
    });

    testWidgets('set: "vergeten" takes the password, then the lock moves too', (tester) async {
      await start(tester, jtSetPin);
      await tester.tap(find.text('Pincode vergeten? Log in met je wachtwoord'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'juist');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await digits(tester, '9999');
      await digits(tester, '9999');
      expectMovedTo('9999');
      await _letSnackExpire(tester);
    });

    testWidgets('set: the lock stays when the new code cannot be saved', (tester) async {
      await start(tester, (context, ref, account) {
        store.serverUp = false;
        return jtSetPin(context, ref, account);
      });
      await digits(tester, '4321');
      await digits(tester, '9999');
      await digits(tester, '9999');
      expectStillLocked();
      await _letSnackExpire(tester);
    });

    testWidgets('set: the lock stays when choosing a new code is cancelled', (tester) async {
      await start(tester, jtSetPin);
      await digits(tester, '4321');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expectStillLocked();
    });

    testWidgets('remove: asks the old code first and leaves no lock', (tester) async {
      await start(tester, jtRemovePin);
      await digits(tester, '0000');
      expect(find.text('Foute pincode, nog 4 pogingen'), findsOneWidget);
      expectStillLocked();
      await digits(tester, '4321');
      final saved = shared.getAccounts().single;
      expect(saved.authMethod, Authentication.autoLogin);
      expect(saved.localPin, isEmpty);
      await _letSnackExpire(tester);
    });

    testWidgets('remove: offline, a copy of the server state is enough for an old lock', (tester) async {
      await start(tester, (context, ref, account) {
        store.serverUp = false;
        return jtRemovePin(context, ref, account);
      });
      await digits(tester, '4321');
      expect(shared.getAccounts().single.localPin, isEmpty);
      expect(find.text('Pincode weggehaald'), findsOneWidget);
      await _letSnackExpire(tester);
    });

    testWidgets('remove: offline without a copy nothing is asked and the old lock stays', (tester) async {
      await start(tester, (context, ref, account) {
        store
          ..serverUp = false
          ..hasCopy = false;
        return jtRemovePin(context, ref, account);
      });
      expect(find.text('Voer de huidige pincode in'), findsNothing);
      expect(find.text('De server is niet bereikbaar. Probeer het later opnieuw.'), findsOneWidget);
      expectStillLocked();
      await _letSnackExpire(tester);
    });

    testWidgets('manage: shows "Met pincode", and "Geen pincode" once the lock is gone', (tester) async {
      await start(tester, (context, ref, account) async {
        ref.read(authProvider.notifier).getSavedAccounts();
        await showJtManageProfiles(context);
      });
      expect(find.text('Met pincode'), findsOneWidget);
      expect(find.text('Pincode wijzigen'), findsOneWidget);
      await tester.tap(find.text('Pincode weghalen'));
      await tester.pumpAndSettle();
      await digits(tester, '4321');
      expect(find.text('Geen pincode'), findsOneWidget);
      expect(find.text('Pincode instellen'), findsOneWidget);
      await _letSnackExpire(tester);
    });
  });
}
