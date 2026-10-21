import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_program_dialog.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';

import 'jt_dvr_test_helpers.dart';

/// B1 (WP2.7c): the "Record" confirmation must show the server pre-padding as
/// "early" and the post-padding as "late". pre != post so a swap is visible.
void main() {
  final program = jtTestProgram(start: DateTime(2026, 10, 21, 20, 0), end: DateTime(2026, 10, 21, 21, 0));
  const defaults = SeriesTimerInfoDto(prePaddingSeconds: 120, postPaddingSeconds: 300);

  Future<void> pumpConfirm(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
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
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showJtRecordConfirmDialog(context, defaults: defaults, program: program, series: false),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('EN: pre=2, post=5 -> starts 2 min early, stops 5 min late', (tester) async {
    await pumpConfirm(tester, const Locale('en'));
    expect(find.textContaining('Starts 2 min early, stops 5 min late'), findsOneWidget);
  });

  testWidgets('NL: pre=2, post=5 -> begint 2 min eerder, stopt 5 min later', (tester) async {
    await pumpConfirm(tester, const Locale('nl'));
    expect(find.textContaining('Begint 2 min eerder, stopt 5 min later'), findsOneWidget);
  });
}
