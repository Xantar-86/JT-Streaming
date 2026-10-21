import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jt/dvr/jt_dvr_permissions.dart';
import 'package:fladder/jt/dvr/jt_program_dialog.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/jt/guide/jt_guide_cache.dart';
import 'package:fladder/jt/guide/jt_guide_controller.dart';
import 'package:fladder/jt/guide/jt_guide_day.dart';
import 'package:fladder/jt/guide/jt_guide_toolbar.dart';
import 'package:fladder/jt/guide/jt_live_tv_guide.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/channel_program.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/live_tv_model.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';

import 'jt_guide_day_test.dart' show noBrussels;
import 'jt_guide_test_helpers.dart';

ChannelModel _channel(String id) => ChannelModel(
      channelId: id,
      id: id,
      name: 'Zender $id',
      startDate: DateTime(2026, 10, 21),
      endDate: DateTime(2026, 10, 21),
      iCurrentProgram: null,
      overview: const OverviewModel(),
      parentId: '',
      playlistId: '',
      images: null,
      childCount: 0,
      primaryRatio: 0,
      userData: const UserData(),
      canDownload: false,
      canDelete: false,
    );

class _FakeLiveTv extends LiveTv {
  @override
  LiveTvModel build() => LiveTvModel(
        startDate: DateTime(2026, 10, 21),
        endDate: DateTime(2026, 10, 21, 16),
        channels: [_channel('c1'), _channel('c3'), _channel('c4')],
      );
}

class _EmptyTimers extends JtTimers {
  @override
  Future<JtTimersState> build() async => JtTimersState.empty;
}

/// Copy of `WidgetsApp._defaultWebShortcuts` (Flutter 3.35.7, widgets/app.dart): on web the arrows are
/// ScrollIntents, not DirectionalFocusIntents. The tests run in the Dart VM (kIsWeb false), so the web
/// mapping is passed explicitly to reproduce the browser (WP2.8c D3).
const Map<ShortcutActivator, Intent> _webDefaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.space): PrioritizedIntents(
    orderedIntents: [
      ActivateIntent(),
      ScrollIntent(direction: AxisDirection.down, type: ScrollIncrementType.page),
    ],
  ),
  SingleActivator(LogicalKeyboardKey.enter): ButtonActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ButtonActivateIntent(),
  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
  SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
  SingleActivator(LogicalKeyboardKey.tab, shift: true): PreviousFocusIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
  SingleActivator(LogicalKeyboardKey.arrowLeft): ScrollIntent(direction: AxisDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight): ScrollIntent(direction: AxisDirection.right),
  SingleActivator(LogicalKeyboardKey.pageUp): ScrollIntent(direction: AxisDirection.up, type: ScrollIncrementType.page),
  SingleActivator(LogicalKeyboardKey.pageDown): ScrollIntent(direction: AxisDirection.down, type: ScrollIncrementType.page),
};

Widget _wrap(Widget child,
        {Locale locale = const Locale('nl'),
        List<Override> overrides = const [],
        Map<ShortcutActivator, Intent>? shortcuts}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        shortcuts: shortcuts,
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
        home: child,
      ),
    );

class _GuidePage extends StatefulWidget {
  final void Function(ChannelProgram program, ChannelModel channel) onSelected;
  const _GuidePage(this.onSelected);
  @override
  State<_GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<_GuidePage> {
  final ScrollController horizontal = ScrollController();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            JtGuideToolbar(horizontalScrollController: horizontal),
            Expanded(child: JtLiveTvGuide(horizontalScrollController: horizontal, onProgramSelected: widget.onSelected)),
          ],
        ),
      );
}

void main() {
  late FakeGuideApi api;
  late DateTime now;
  final selected = <String>[];

  List<Override> overrides() => [
        liveTvProvider.overrideWith(_FakeLiveTv.new),
        jtGuideApiProvider.overrideWithValue(api),
        jtGuideClockProvider.overrideWithValue(() => now),
        jtTimersProvider.overrideWith(_EmptyTimers.new),
        jtCanManageRecordingsProvider.overrideWithValue(false),
      ];

  setUp(() {
    api = FakeGuideApi()..coverageResult = (DateTime(2026, 10, 19, 4), DateTime(2026, 10, 27, 6));
    now = DateTime(2026, 10, 21, 18, 44);
    selected.clear();
  });

  Future<JtGuideController> pumpGuide(WidgetTester tester,
      {Locale locale = const Locale('nl'), double width = 1920, Map<ShortcutActivator, Intent>? shortcuts}) async {
    tester.view.physicalSize = Size(width, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      _GuidePage((program, channel) => selected.add(program.id)),
      locale: locale,
      overrides: overrides(),
      shortcuts: shortcuts,
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(JtLiveTvGuide)));
    return container.read(jtGuideControllerProvider);
  }

  FocusNode focused() => FocusManager.instance.primaryFocus!;

  Future<void> focusCell(WidgetTester tester, JtGuideController guide, String channel, {required bool last}) async {
    final cells = guide.rows[channel]!.cells;
    (last ? cells.last : cells.first).requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets('opens on today at now: now line visible, window header in NL', (tester) async {
    final guide = await pumpGuide(tester);
    expect(guide.day, const JtGuideDay(2026, 10, 21));
    expect(find.byKey(const ValueKey('jt-guide-now-line')), findsOneWidget);
    // 18:44 - 10 min lead = 18:34; viewport 1920 - 175 = 1745 px = 174.5 min.
    expect(find.text('woensdag 21 oktober · 18:34–21:28'), findsOneWidget);
  });

  // Les B1: the rendered text with placeholders, NL and EN.
  testWidgets('header text rendered NL: "woensdag 21 oktober · 18:00–20:45"', (tester) async {
    final guide = await pumpGuide(tester, width: 175 + 1650);
    guide.scroll!.jumpTo(const JtGuideDay(2026, 10, 21).offsetOf(DateTime(2026, 10, 21, 18)));
    await tester.pumpAndSettle();
    expect(find.text('woensdag 21 oktober · 18:00–20:45'), findsOneWidget);
    expect(find.text('Dag: wo 21 okt.'), findsOneWidget);
    expect(find.text('Uur: 18:00'), findsOneWidget);
    expect(find.text('Eerder'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('header text rendered EN: "Wednesday 21 October · 18:00–20:45"', (tester) async {
    final guide = await pumpGuide(tester, locale: const Locale('en'), width: 175 + 1650);
    guide.scroll!.jumpTo(const JtGuideDay(2026, 10, 21).offsetOf(DateTime(2026, 10, 21, 18)));
    await tester.pumpAndSettle();
    expect(find.text('Wednesday 21 October · 18:00–20:45'), findsOneWidget);
    expect(find.text('Day: Wed 21 Oct'), findsOneWidget);
    expect(find.text('Hour: 18:00'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
  });

  testWidgets('arrow right on the last program -> tomorrow, focus on the first program of the same channel',
      (tester) async {
    final guide = await pumpGuide(tester);
    await focusCell(tester, guide, 'c3', last: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 22));
    expect(guide.rowOf(focused())?.channelId, 'c3');
    expect(guide.rows['c3']!.cells.first, focused());
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected.last, 'c3-h0');
  });

  testWidgets('arrow left on the first program -> yesterday, focus on the last program of the same channel',
      (tester) async {
    final guide = await pumpGuide(tester);
    await focusCell(tester, guide, 'c4', last: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 20));
    expect(guide.rowOf(focused())?.channelId, 'c4');
    expect(guide.rows['c4']!.cells.last, focused());
  });

  testWidgets('arrow right inside a row stays on the same day and channel', (tester) async {
    final guide = await pumpGuide(tester);
    await focusCell(tester, guide, 'c1', last: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 21));
    expect(guide.rows['c1']!.cells[1], focused());
  });

  group('web default shortcuts (arrows = ScrollIntent)', () {
    testWidgets('arrow left on the first program -> yesterday, focus on the last program of the same channel',
        (tester) async {
      final guide = await pumpGuide(tester, shortcuts: _webDefaultShortcuts);
      await focusCell(tester, guide, 'c4', last: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(guide.day, const JtGuideDay(2026, 10, 20));
      expect(guide.rowOf(focused())?.channelId, 'c4');
      expect(guide.rows['c4']!.cells.last, focused());
    });

    testWidgets('arrow right on the last program -> tomorrow, focus on the first program of the same channel',
        (tester) async {
      final guide = await pumpGuide(tester, shortcuts: _webDefaultShortcuts);
      await focusCell(tester, guide, 'c3', last: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(guide.day, const JtGuideDay(2026, 10, 22));
      expect(guide.rowOf(focused())?.channelId, 'c3');
      expect(guide.rows['c3']!.cells.first, focused());
    });

    testWidgets('arrows between cells move the focus: right/left in the row, down/up to another channel',
        (tester) async {
      final guide = await pumpGuide(tester, shortcuts: _webDefaultShortcuts);
      await focusCell(tester, guide, 'c1', last: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(guide.day, const JtGuideDay(2026, 10, 21));
      expect(guide.rows['c1']!.cells[1], focused());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(guide.rows['c1']!.cells[0], focused());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(guide.rowOf(focused())?.channelId, 'c3');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(guide.rowOf(focused())?.channelId, 'c1');
      expect(guide.day, const JtGuideDay(2026, 10, 21));
    });
  });

  testWidgets('no day change past the last day of the coverage', (tester) async {
    api.coverageResult = (DateTime(2026, 10, 21, 4), DateTime(2026, 10, 21, 20, 38));
    final guide = await pumpGuide(tester);
    await focusCell(tester, guide, 'c1', last: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 21));
  });

  testWidgets('PageDown/PageUp and the aliases change the day, same clock time and channel', (tester) async {
    final guide = await pumpGuide(tester);
    await focusCell(tester, guide, 'c1', last: false);
    guide.rows['c1']!.cells[18].requestFocus(); // 18:00-19:00
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 22));
    expect(guide.rowOf(focused())?.channelId, 'c1');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected.last, 'c1-h18');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 21));
    for (final (key, day) in [
      (LogicalKeyboardKey.channelDown, 22),
      (LogicalKeyboardKey.channelUp, 21),
      (LogicalKeyboardKey.mediaFastForward, 22),
      (LogicalKeyboardKey.mediaRewind, 21),
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(guide.day, JtGuideDay(2026, 10, day), reason: key.debugName);
    }
  });

  testWidgets('Now from another day: today, now line, focus on the running program', (tester) async {
    final guide = await pumpGuide(tester);
    await focusCell(tester, guide, 'c4', last: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jt-guide-now-line')), findsNothing);
    await tester.tap(find.text('Nu'));
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 21));
    expect(find.byKey(const ValueKey('jt-guide-now-line')), findsOneWidget);
    expect(guide.rowOf(focused())?.channelId, 'c4');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected.last, 'c4-h18', reason: 'now = 18:44');
  });

  testWidgets('Earlier/Later: 2 h on a wide screen, over midnight the day changes', (tester) async {
    final guide = await pumpGuide(tester);
    guide.pickHour(23);
    await tester.pumpAndSettle();
    expect(guide.stepMinutes, 120);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 22));
    expect(guide.anchor, DateTime(2026, 10, 22, 1));
    await tester.tap(find.text('Eerder'));
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 21));
    expect(guide.anchor, DateTime(2026, 10, 21, 23));
  });

  testWidgets('day and hour pickers', (tester) async {
    final guide = await pumpGuide(tester);
    await tester.tap(find.text('Dag: wo 21 okt.'));
    await tester.pumpAndSettle();
    expect(find.text('Kies een dag'), findsOneWidget);
    expect(find.text('Gisteren'), findsOneWidget);
    expect(find.text('Vandaag'), findsOneWidget);
    expect(find.text('Morgen'), findsOneWidget);
    expect(find.text('vr 23 okt.'), findsOneWidget);
    await tester.tap(find.text('Morgen'));
    await tester.pumpAndSettle();
    expect(guide.day, const JtGuideDay(2026, 10, 22));
    await tester.tap(find.text('Uur: 18:00'));
    await tester.pumpAndSettle();
    expect(find.text('Kies een uur'), findsOneWidget);
    expect(find.text('00:00'), findsWidgets);
    await tester.tap(find.widgetWithText(ElevatedButton, '06:00'));
    await tester.pumpAndSettle();
    expect(guide.anchor, DateTime(2026, 10, 22, 6));
    expect(find.text('Dag: do 22 okt.'), findsOneWidget);
  });

  testWidgets('25/10/2026: 25 h timeline (15000 px), "02:00" twice, hour picker 02:00 = first', (tester) async {
    now = DateTime(2026, 10, 25, 12);
    final guide = await pumpGuide(tester);
    expect(guide.day.timelineWidth, 15000);
    expect(find.text('02:00'), findsNWidgets(2));
    guide.pickHour(2);
    await tester.pumpAndSettle();
    expect(guide.anchor.timeZoneOffset, const Duration(hours: 2));
  }, skip: noBrussels != null);

  testWidgets('Back pops the guide route; Escape closes an open dialog first', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GuidePage((p, c) {}))),
          child: const Text('open'),
        ),
      ),
      overrides: overrides(),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dag: wo 21 okt.'));
    await tester.pumpAndSettle();
    expect(find.text('Kies een dag'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Kies een dag'), findsNothing);
    expect(find.byType(JtLiveTvGuide), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(JtLiveTvGuide), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('program dialog (§5)', () {
    Future<void> openDialog(WidgetTester tester, ChannelProgram program, Locale locale) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showJtProgramDialog(context, program: program, channel: _channel('c1'), onWatch: () {}),
            child: const Text('open'),
          ),
        ),
        locale: locale,
        overrides: overrides(),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final past = guideProgram('p', 'c1', DateTime(2026, 1, 7, 20), DateTime(2026, 1, 7, 20, 30));
    final future = guideProgram('f', 'c1', DateTime(2099, 1, 7, 20), DateTime(2099, 1, 7, 20, 30));

    testWidgets('past program NL: info only, "Al uitgezonden", close', (tester) async {
      await openDialog(tester, past, const Locale('nl'));
      expect(find.text('Al uitgezonden'), findsOneWidget);
      expect(find.text('p op Zender c1, wo 7 jan. 20:00–20:30'), findsOneWidget);
      expect(find.text('Sluiten'), findsOneWidget);
      expect(find.text('Kijken'), findsNothing);
      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(find.text('Al uitgezonden'), findsNothing);
    });

    testWidgets('past program EN: "Already aired"', (tester) async {
      await openDialog(tester, past, const Locale('en'));
      expect(find.text('Already aired'), findsOneWidget);
      expect(find.text('p on Zender c1, Wed 7 Jan 20:00–20:30'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('future program keeps the switch-channel dialog with Watch', (tester) async {
      await openDialog(tester, future, const Locale('en'));
      expect(find.text('Already aired'), findsNothing);
      expect(find.text('Watch'), findsOneWidget);
    });
  });
}
