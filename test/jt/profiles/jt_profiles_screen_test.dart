import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/jt/profiles/jt_pin_pad.dart';
import 'package:fladder/jt/profiles/jt_profile_flow.dart';
import 'package:fladder/jt/profiles/jt_profiles_screen.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/shared_provider.dart';

AccountModel _account(String name, {int minutesAgo = 60}) => AccountModel(
      name: name,
      id: 'id-$name',
      avatar: '',
      lastUsed: DateTime(2026, 10, 30, 20).subtract(Duration(minutes: minutesAgo)),
      credentials: CredentialsModel.internal(url: 'https://tv.example', serverId: 'srv', token: 't-$name'),
    );

Future<void> _pump(WidgetTester tester, Widget home, {Size size = const Size(1920, 1080)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

void main() {
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
}
