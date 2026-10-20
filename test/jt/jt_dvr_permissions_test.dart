import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_permissions.dart';
import 'package:fladder/jt/dvr/jt_record_buttons.dart';
import 'package:fladder/jt/dvr/jt_scheduled_recordings_page.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/user_provider.dart';

import 'jt_dvr_test_helpers.dart';

class _FakeUser extends User {
  _FakeUser(this.account);
  final AccountModel? account;

  @override
  AccountModel? build() => account;
}

class _FixedTimers extends JtTimers {
  @override
  Future<JtTimersState> build() async => JtTimersState.empty;
}

AccountModel _account(bool manage) => AccountModel(
      name: 'forge-test',
      id: 'u1',
      avatar: '',
      lastUsed: DateTime(2026),
      credentials: CredentialsModel.internal(),
      policy: UserPolicy(
        enableLiveTvManagement: manage,
        authenticationProviderId: '',
        passwordResetProviderId: '',
      ),
    );

Future<void> _pump(WidgetTester tester, AccountModel? account) async {
  final now = DateTime.now();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith(() => _FakeUser(account)),
        jtTimersProvider.overrideWith(_FixedTimers.new),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              JtRecordButtons(
                program: jtTestProgram(
                  start: now.add(const Duration(hours: 1)),
                  end: now.add(const Duration(hours: 2)),
                ),
              ),
              const JtScheduledRecordingsButton(),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('jtCanManageRecordings follows Policy.EnableLiveTvManagement', () {
    expect(jtCanManageRecordings(null), isFalse);
    expect(jtCanManageRecordings(_account(false)), isFalse);
    expect(jtCanManageRecordings(_account(true)), isTrue);
  });

  testWidgets('without EnableLiveTvManagement no recording buttons are shown', (tester) async {
    await _pump(tester, _account(false));
    expect(find.text('Record'), findsNothing);
    expect(find.text('Scheduled recordings'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('without a user no recording buttons are shown', (tester) async {
    await _pump(tester, null);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('with EnableLiveTvManagement a future program can be recorded', (tester) async {
    await _pump(tester, _account(true));
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Scheduled recordings'), findsOneWidget);
  });
}
