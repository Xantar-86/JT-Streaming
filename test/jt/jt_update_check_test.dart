import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jt/web/jt_update_check.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';

void main() {
  group('jtIsNewerBuild', () {
    const running = '0.11.1-jt.6+6000';
    test('another build id on the server -> update', () {
      expect(jtIsNewerBuild('{"buildId":"0.11.1-jt.6+6001"}', running), isTrue);
    });
    test('same build id -> no update', () {
      expect(jtIsNewerBuild('{"buildId":"0.11.1-jt.6+6000","version":"0.11.1-jt.6"}', running), isFalse);
    });
    test('jt.5.2 buildinfo has no buildId -> no update (no false alarm)', () {
      expect(jtIsNewerBuild('{"version":"0.11.1-jt.5.2","buildNumber":5002}', running), isFalse);
    });
    test('dev build (no JT_BUILD_ID), missing or broken file -> no update', () {
      expect(jtIsNewerBuild('{"buildId":"x"}', ''), isFalse);
      expect(jtIsNewerBuild(null, running), isFalse);
      expect(jtIsNewerBuild('<html>', running), isFalse);
    });
  });

  testWidgets('not on web: the check renders only its child and starts no timers', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: JtUpdateCheck(runningBuildId: '0.11.1-jt.6+6000', child: Text('app')),
    ));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('app'), findsOneWidget);
    expect(find.text('New version available'), findsNothing);
  });
}
