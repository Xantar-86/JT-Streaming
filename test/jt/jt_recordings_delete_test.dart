import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jt/dvr/jt_dvr_service.dart';
import 'package:fladder/jt/dvr/jt_recordings_provider.dart';
import 'package:fladder/jt/dvr/jt_scheduled_recordings_page.dart';
import 'package:fladder/jt/dvr/jt_timers_provider.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';

/// Eis board d8f91bfb: a finished recording can be deleted from the recordings
/// page, with a confirmation, with the D-pad, and only where CanDelete is true.
class _OpenApi extends Fake implements JellyfinOpenApi {
  _OpenApi(this.service);
  final _Service service;

  @override
  Future<chopper.Response<BaseItemDtoQueryResult>> liveTvRecordingsGet({
    String? channelId,
    String? userId,
    int? startIndex,
    int? limit,
    LiveTvRecordingsGetStatus? status,
    bool? isInProgress,
    String? seriesTimerId,
    bool? enableImages,
    int? imageTypeLimit,
    List<ImageType>? enableImageTypes,
    List<ItemFields>? fields,
    bool? enableUserData,
    bool? isMovie,
    bool? isSeries,
    bool? isKids,
    bool? isSports,
    bool? isNews,
    bool? isLibraryItem,
    bool? enableTotalRecordCount,
  }) async {
    service.requestedFields = fields;
    if (service.listStatus != 200) {
      return chopper.Response(http.Response('', service.listStatus), null);
    }
    return chopper.Response(
      http.Response('', 200),
      BaseItemDtoQueryResult(items: List.of(service.recordings)),
    );
  }
}

class _Service extends Fake implements JellyService {
  _Service(this.recordings);
  final List<BaseItemDto> recordings;
  final List<String> deleted = [];
  List<ItemFields>? requestedFields;
  int listStatus = 200;
  int deleteStatus = 204;
  bool deleteThrows = false;

  @override
  JellyfinOpenApi get api => _OpenApi(this);

  @override
  Future<chopper.Response<dynamic>> deleteItem(String itemId) async {
    if (deleteThrows) throw Exception('no network');
    deleted.add(itemId);
    if (deleteStatus == 204) recordings.removeWhere((r) => r.id == itemId);
    return chopper.Response(http.Response('', deleteStatus), null);
  }
}

class _Api extends JellyApi {
  _Api(this.service);
  final JellyService service;

  @override
  JellyService build() => service;
}

class _FakeUser extends User {
  _FakeUser({this.manage = true});
  final bool manage;

  @override
  AccountModel? build() => AccountModel(
        name: 'jochen',
        id: 'u1',
        avatar: '',
        lastUsed: DateTime(2026),
        credentials: CredentialsModel.internal(),
        policy: UserPolicy(
          enableLiveTvManagement: manage,
          enableLiveTvAccess: true,
          authenticationProviderId: '',
          passwordResetProviderId: '',
        ),
      );
}

class _Timers extends JtTimers {
  _Timers(this.initial);
  final JtTimersState initial;

  @override
  Future<JtTimersState> build() async => initial;
}

BaseItemDto _recording(String id, {bool? canDelete = true, BaseItemKind type = BaseItemKind.episode, String? status}) =>
    BaseItemDto(
      id: id,
      name: 'VTM Nieuws',
      type: type,
      canDelete: canDelete,
      status: status,
      channelName: 'VTM',
      startDate: DateTime(2026, 10, int.parse(id), 19, 0),
      runTimeTicks: 18000000000,
    );

/// The tests run in the Dart VM; on web the arrows are ScrollIntents (WP2.8c D3).
const Map<ShortcutActivator, Intent> _webShortcuts = {
  SingleActivator(LogicalKeyboardKey.enter): ButtonActivateIntent(),
  SingleActivator(LogicalKeyboardKey.tab): NextFocusIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
  SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
  SingleActivator(LogicalKeyboardKey.arrowLeft): ScrollIntent(direction: AxisDirection.left),
  SingleActivator(LogicalKeyboardKey.arrowRight): ScrollIntent(direction: AxisDirection.right),
};

Future<void> _pump(WidgetTester tester, _Service service,
    {Map<ShortcutActivator, Intent>? shortcuts, bool manage = true, JtTimersState timers = JtTimersState.empty}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith(() => _FakeUser(manage: manage)),
        jtTimersProvider.overrideWith(() => _Timers(timers)),
        jellyApiProvider.overrideWith(() => _Api(service)),
      ],
      child: MaterialApp(
        shortcuts: shortcuts,
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // AdaptiveLayoutModel does not set this: on a remote the real app does (adaptive_layout.dart).
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: AdaptiveLayout(
            data: AdaptiveLayoutModel(
              viewSize: ViewSize.television,
              layoutMode: LayoutMode.dual,
              inputDevice: InputDevice.dPad,
              platform: TargetPlatform.android,
              isDesktop: false,
              posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
              controller: {for (final tab in HomeTabs.values) tab: ScrollController()},
              sideBarWidth: 0,
              topBarHeight: 0,
              statusBarHeight: 0,
            ),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) {
            FladderSnack.setContext(context);
            return const JtScheduledRecordingsPage();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _focusedText(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final text = find.descendant(of: find.byWidget(context.widget), matching: find.byType(Text));
  return text.evaluate().isEmpty ? null : tester.widget<Text>(text.first).data;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// Walks down with the D-pad until a button with this label has the focus.
Future<void> _downTo(WidgetTester tester, String label) async {
  for (var i = 0; i < 6 && _focusedText(tester) != label; i++) {
    await _key(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(_focusedText(tester), label);
}

AnimatedContainer? _ring() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<AnimatedContainer>();

/// Whether the row or heading with the focus shows the ring.
bool _ringVisible() {
  final border = (_ring()?.decoration as BoxDecoration?)?.border as Border?;
  return border != null && border.top.color != Colors.transparent;
}

/// The ring, and so all lines of the row, lies inside the list.
void _expectRowOnScreen(WidgetTester tester, {String? reason}) {
  final ring = tester.getRect(find.byWidget(_ring()!));
  final list = tester.getRect(find.byType(ListView));
  expect(ring.top, greaterThanOrEqualTo(list.top), reason: reason);
  expect(ring.bottom, lessThanOrEqualTo(list.bottom), reason: reason);
}

final _timers = JtTimersState.from(
  [
    TimerInfoDto(id: 't1', name: 'Film', channelName: 'VTM', status: RecordingStatus.$new, startDate: DateTime(2026, 11, 2, 20)),
    TimerInfoDto(id: 't2', name: 'Journaal', channelName: 'VRT', status: RecordingStatus.inprogress, startDate: DateTime(2026, 11, 2, 21)),
  ],
  const [SeriesTimerInfoDto(id: 's1', name: 'Reeks')],
);

void main() {
  group('jtCanDeleteRecording', () {
    test('only an explicit CanDelete=true of a finished recording', () {
      expect(jtCanDeleteRecording(_recording('1')), isTrue);
      expect(jtCanDeleteRecording(_recording('1', canDelete: false)), isFalse);
      expect(jtCanDeleteRecording(_recording('1', canDelete: null)), isFalse);
      expect(jtCanDeleteRecording(const BaseItemDto(canDelete: true)), isFalse);
    });

    test('a running recording is never deletable, whatever the server says', () {
      expect(jtCanDeleteRecording(_recording('1', type: BaseItemKind.recording)), isFalse);
      expect(jtCanDeleteRecording(_recording('1', status: 'InProgress')), isFalse);
      expect(jtCanDeleteRecording(_recording('1', status: 'Completed')), isTrue);
    });
  });

  group('service', () {
    test('the list asks for CanDelete: the server leaves it out otherwise', () async {
      final service = _Service([_recording('1')]);
      await service.jtRecordings();
      expect(service.requestedFields, contains(ItemFields.candelete));
    });

    test('a failed list throws, so it does not look like "no recordings"', () async {
      final service = _Service([])..listStatus = 500;
      await expectLater(service.jtRecordings(), throwsException);
    });

    test('delete goes through DELETE /Items and reports 401 and no network as failure', () async {
      final service = _Service([_recording('1')]);
      expect(await service.jtDeleteRecording('1'), isTrue);
      expect(service.deleted, ['1']);
      expect(await (service..deleteStatus = 401).jtDeleteRecording('1'), isFalse);
      expect(await (service..deleteThrows = true).jtDeleteRecording('1'), isFalse);
    });
  });

  testWidgets('the delete button shows only where CanDelete is true', (tester) async {
    await _pump(
        tester, _Service([_recording('1', canDelete: false), _recording('2'), _recording('3', status: 'InProgress')]));
    expect(find.text('Opgenomen'), findsOneWidget);
    expect(find.text('Verwijderen'), findsOneWidget);
    expect(find.text('VTM Nieuws'), findsNWidgets(3));
    expect(find.textContaining('02/10/2026 19:00'), findsOneWidget);
  });

  testWidgets('without any right the list has no delete button', (tester) async {
    await _pump(tester, _Service([_recording('1', canDelete: false)]));
    expect(find.text('Verwijderen'), findsNothing);
  });

  testWidgets('D-pad: the dialog opens on the safe button, declining deletes nothing', (tester) async {
    final service = _Service([_recording('1')]);
    await _pump(tester, service);
    await _downTo(tester, 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.textContaining('definitief verwijderen'), findsOneWidget);
    // In the row and in the dialog: a daily show needs the date to tell them apart.
    expect(find.textContaining('01/10/2026 19:00'), findsNWidgets(2));
    expect(_focusedText(tester), isNot('Verwijderen'));

    await _key(tester, LogicalKeyboardKey.select);
    expect(find.textContaining('definitief verwijderen'), findsNothing);
    expect(service.deleted, isEmpty);
  });

  testWidgets('D-pad: delete one, the list updates and the next one stays reachable', (tester) async {
    final service = _Service([_recording('1'), _recording('2')]);
    await _pump(tester, service);
    await _downTo(tester, 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedText(tester), 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.select);

    expect(service.deleted, ['1']);
    expect(find.text('VTM Nieuws'), findsOneWidget);
    expect(find.text('Opname verwijderd'), findsOneWidget);

    await _downTo(tester, 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.textContaining('02/10/2026 19:00'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('web: the arrows reach the button and the dialog too', (tester) async {
    final service = _Service([_recording('1')]);
    await _pump(tester, service, shortcuts: _webShortcuts);
    await _downTo(tester, 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedText(tester), 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(service.deleted, ['1']);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('fe06253c: Live TV access is enough, the server decides per recording', (tester) async {
    final service = _Service([_recording('1'), _recording('2', canDelete: false)]);
    await _pump(tester, service, manage: false);
    expect(find.text('VTM Nieuws'), findsNWidgets(2));
    expect(find.text('Verwijderen'), findsOneWidget);
    expect(find.text('Komende opnames'), findsNothing);

    await _downTo(tester, 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.select);
    expect(service.deleted, ['1']);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a refused delete keeps the recording and says so', (tester) async {
    final service = _Service([_recording('1')])..deleteStatus = 401;
    await _pump(tester, service);
    await _downTo(tester, 'Verwijderen');
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.select);

    expect(find.text('VTM Nieuws'), findsOneWidget);
    expect(find.text('Opname verwijderen mislukt'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('a failing list does not hide the scheduled part', (tester) async {
    await _pump(tester, _Service([])..listStatus = 500);
    expect(find.text('Opnames laden mislukt'), findsOneWidget);
    expect(find.text('Komende opnames'), findsOneWidget);
  });

  group('directional (B9)', () {
    testWidgets('every button is reachable, also past a row without one, and each stop shows the focus',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        _Service([_recording('1'), _recording('2', status: 'InProgress'), _recording('3')]),
        timers: _timers,
      );

      expect(_focusedText(tester), 'Opgenomen');
      final stops = <String?>[];
      for (var i = 0; i < 6; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
        stops.add(_focusedText(tester));
        expect(_ringVisible(), isTrue, reason: 'stop $i: ${stops.last}');
      }
      expect(stops, [
        'Verwijderen',
        'VTM Nieuws',
        'Verwijderen',
        'Reeks annuleren',
        'Opname annuleren',
        'Stop opname',
      ]);

      // And back up the same way.
      final back = <String?>[];
      for (var i = 0; i < 6; i++) {
        await _key(tester, LogicalKeyboardKey.arrowUp);
        back.add(_focusedText(tester));
      }
      expect(back, ['Opname annuleren', 'Reeks annuleren', 'Verwijderen', 'VTM Nieuws', 'Verwijderen', 'Opgenomen']);
    });

    testWidgets('OK on each kind of button opens its dialog, declining puts the focus back', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, _Service([_recording('1')]), timers: _timers);

      for (final label in ['Verwijderen', 'Reeks annuleren', 'Opname annuleren', 'Stop opname']) {
        await _downTo(tester, label);
        await _key(tester, LogicalKeyboardKey.select);
        expect(find.byType(AlertDialog), findsOneWidget, reason: label);
        await _key(tester, LogicalKeyboardKey.select);
        expect(find.byType(AlertDialog), findsNothing, reason: label);
        expect(_focusedText(tester), label);
      }
    });

    testWidgets('a long list without buttons scrolls to the end and back with the D-pad', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final items = [for (var i = 1; i <= 28; i++) _recording('$i', canDelete: false)];
      await _pump(tester, _Service(items), manage: false);

      final position = tester.state<ScrollableState>(find.byType(Scrollable).last).position;
      for (var i = 0; i < 28; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(_focusedText(tester), 'VTM Nieuws', reason: 'row $i');
        expect(_ringVisible(), isTrue, reason: 'row $i');
        _expectRowOnScreen(tester, reason: 'row $i');
      }
      expect(position.pixels, position.maxScrollExtent);
      expect(position.maxScrollExtent, greaterThan(0));

      for (var i = 0; i < 28; i++) {
        await _key(tester, LogicalKeyboardKey.arrowUp);
        _expectRowOnScreen(tester, reason: 'row $i');
      }
      expect(_focusedText(tester), 'Opgenomen');
      expect(position.pixels, 0);
    });

    testWidgets('a button deep in a long list is reached and shown', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final items = [for (var i = 1; i <= 19; i++) _recording('$i', canDelete: false), _recording('20')];
      await _pump(tester, _Service(items));

      for (var i = 0; i < 20; i++) {
        await _key(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(_focusedText(tester), 'Verwijderen');
      _expectRowOnScreen(tester);
    });
  });
}
