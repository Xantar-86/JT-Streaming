import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/channel_program.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/live_tv_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/incognito_mode_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/poster_defaults.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

// Reviewer, THEAAA-190 ronde 4: aanvalsproeven op bfe5dda1, momenten die jt_live_stream_cancel_test.dart niet raakt.

final _refProvider = Provider<Ref>((ref) => ref);

class _Service implements JellyService {
  final List<String> calls = [];
  Completer<void>? holdStop;
  chopper.Response<void> get _ok => chopper.Response(http.Response('', 204), null);

  @override
  Future<chopper.Response> sessionsPlayingStoppedPost({required PlaybackStopInfo? body}) async {
    calls.add('stopped:${body?.liveStreamId}');
    await holdStop?.future;
    return _ok;
  }

  @override
  Future<chopper.Response> liveStreamsClosePost({required String liveStreamId}) async {
    calls.add('close:$liveStreamId');
    return _ok;
  }

  @override
  Future<chopper.Response> sessionsPlayingPost({required PlaybackStartInfo? body}) async {
    calls.add('playing:${body?.liveStreamId}');
    return _ok;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends JellyApi {
  _Api(this.service);
  final JellyService service;
  @override
  JellyService build() => service;
}

class _LiveTv extends LiveTv {
  @override
  LiveTvModel build() => LiveTvModel(startDate: DateTime(2026), endDate: DateTime(2026));
  @override
  Future<LiveTvModel> fetchDashboard() async => state;
  @override
  Future<List<ChannelProgram>> fetchPrograms(ChannelModel channelProgram) async => [];
}

class _Opening {
  Completer<PlaybackModel?> next = Completer();
}

class _Helper extends PlaybackModelHelper {
  const _Helper(this.opening, {required super.ref});
  final _Opening opening;

  @override
  Future<PlaybackModel?> createPlaybackModel(
    BuildContext? context,
    ItemBaseModel? item, {
    PlaybackModel? oldModel,
    List<ItemBaseModel>? libraryQueue,
    PlaybackQueueSource? queueSource,
    bool showPlaybackOptions = false,
    PlaybackType? forcedPlaybackType,
    Duration? startPosition,
  }) =>
      opening.next.future;
}

class _Player extends BasePlayer {
  final List<String> calls = [];
  Completer<void>? holdLoad;
  Completer<void>? holdAudioTrack;
  bool failLoad = false;
  final _states = StreamController<PlayerState>.broadcast();

  @override
  Stream<PlayerState> get stateStream => _states.stream;
  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {}
  @override
  Widget? videoWidget(Key key, BoxFit fit) => null;
  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;
  @override
  Future<void> dispose() async {}
  @override
  Future<void> open(BuildContext context) async => calls.add('open');
  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    calls.add('load:$url');
    final hold = holdLoad;
    holdLoad = null;
    await hold?.future;
    if (failLoad) throw Exception('load failed');
  }

  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> playOrPause() async {}
  @override
  Future<void> loop(bool loop) async {}
  @override
  Future<Uint8List?> takeScreenshot() async => null;
  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => -1;
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    calls.add('audioTrack');
    await holdAudioTrack?.future;
    return -1;
  }
}

void main() {
  late _Service service;
  late _Player player;
  late _Opening opening;
  late ProviderContainer container;

  ChannelModel channel(String id) => ChannelModel.fromBaseDto(
        BaseItemDto(id: id, name: id, type: BaseItemKind.tvchannel),
        container.read(_refProvider),
      );

  TvPlaybackModel tv(String stream, {String? session}) {
    final item = channel(stream);
    return TvPlaybackModel(
      channel: item,
      item: item,
      media: Media(url: 'http://jf/$stream'),
      playbackInfo: PlaybackInfoResponse(
        playSessionId: session ?? 'session-$stream',
        mediaSources: [MediaSourceInfo(id: 'source', liveStreamId: stream)],
      ),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    TvPlaybackModel.resetClosedLiveStreams();
    service = _Service();
    player = _Player();
    opening = _Opening();
    container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _Api(service)),
      incognitoProvider.overrideWith((ref) => false),
      liveTvProvider.overrideWith(_LiveTv.new),
      videoPlayerProvider.overrideWith((ref) => VideoPlayerNotifier(ref)),
      playbackModelHelper.overrideWith((ref) => _Helper(opening, ref: ref)),
    ]);
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      try {
        await container.read(videoPlayerProvider).setup(player);
      } catch (_) {}
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AdaptiveLayout(
            data: AdaptiveLayoutModel(
              viewSize: ViewSize.phone,
              layoutMode: LayoutMode.single,
              inputDevice: InputDevice.pointer,
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => channel('new').play(context, ref).catchError((Object _) {}),
                child: const Text('zender'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> startChannel(WidgetTester tester) async {
    await tester.tap(find.text('zender'), warnIfMissed: false);
    await tester.pump();
  }

  Future<void> tapX(WidgetTester tester) async {
    await tester.tap(find.byIcon(IconsaxPlusLinear.close_square));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester, [int ms = 500]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('R1 X tijdens stopBeforeLoad, daarna opnieuw een zender: speelt en stopt nog normaal', (tester) async {
    await pumpApp(tester);
    container.read(playBackModel.notifier).state = tv('old');
    service.holdStop = Completer();
    await startChannel(tester);
    opening.next.complete(tv('first'));
    await tester.pump();
    await tapX(tester);
    service.holdStop!.complete();
    service.holdStop = null;
    await settle(tester);
    expect(service.calls, ['stopped:old', 'stopped:first']);
    expect(find.text('zender'), findsOneWidget);

    opening.next = Completer();
    await startChannel(tester);
    opening.next.complete(tv('second'));
    await settle(tester);

    expect(player.calls, containsAllInOrder(['load:http://jf/second', 'play', 'open']));
    expect((container.read(playBackModel) as TvPlaybackModel).liveStreamId, 'second');
    expect(service.calls, isNot(contains('stopped:second')));

    unawaited(container.read(videoPlayerProvider).stop());
    await settle(tester);
    expect(service.calls, contains('stopped:second'));
    expect(container.read(playBackModel), isNull);
  });

  testWidgets('R2 X tijdens loadVideo, daarna meteen opnieuw een zender terwijl de oude load nog loopt', (tester) async {
    await pumpApp(tester);
    final held = Completer<void>();
    player.holdLoad = held;
    await startChannel(tester);
    opening.next.complete(tv('first'));
    await settle(tester);
    await tapX(tester);
    expect(service.calls, ['stopped:first']);

    opening.next = Completer();
    await startChannel(tester);
    opening.next.complete(tv('second'));
    await settle(tester);

    held.complete();
    await settle(tester);

    final playing = container.read(playBackModel);
    // Ofwel speelt second, ofwel is second ook gesloten. Nooit: second open zonder speler.
    final open = playing is TvPlaybackModel && playing.liveStreamId == 'second';
    expect(open || service.calls.contains('stopped:second'), isTrue, reason: '${service.calls} ${player.calls}');
    expect(service.calls.where((c) => c == 'stopped:first').length, 1);
    debugPrint('R2 service=${service.calls} player=${player.calls}');
    unawaited(container.read(videoPlayerProvider).stop());
    await settle(tester);
  });

  testWidgets('R3 loadVideo faalt na de X: stream dicht, geen speler', (tester) async {
    await pumpApp(tester);
    final held = Completer<void>();
    player.holdLoad = held;
    player.failLoad = true;
    await startChannel(tester);
    opening.next.complete(tv('new'));
    await settle(tester);
    await tapX(tester);
    held.complete();
    await settle(tester);
    tester.takeException();

    expect(service.calls, ['stopped:new']);
    expect(player.calls, isNot(contains('open')));
    expect(container.read(playBackModel), isNull);
  });

  testWidgets('R4 loadVideo faalt zonder X: de X sluit de stream daarna alsnog', (tester) async {
    await pumpApp(tester);
    player.failLoad = true;
    await startChannel(tester);
    opening.next.complete(tv('new'));
    await settle(tester);
    tester.takeException();

    expect(find.byIcon(IconsaxPlusLinear.close_square), findsOneWidget, reason: 'dialoog hoort nog te staan');
    await tapX(tester);
    await settle(tester);
    expect(service.calls, ['stopped:new']);
    expect(container.read(playBackModel), isNull);
  });

  testWidgets('R5 X terwijl Stopped hangt: geen Close, geen dubbele Stopped', (tester) async {
    await pumpApp(tester);
    player.holdAudioTrack = Completer();
    service.holdStop = Completer();
    await startChannel(tester);
    opening.next.complete(tv('new'));
    await settle(tester);

    await tapX(tester);
    await tester.pump(const Duration(seconds: 12));
    expect(service.calls, ['stopped:new']);

    player.holdAudioTrack!.complete();
    await settle(tester);
    expect(service.calls, ['stopped:new']);
    expect(player.calls, isNot(contains('play')));
    expect(container.read(playBackModel), isNull);
  });

  testWidgets('R6 X en PlaybackInfo faalt daarna: geen verzoeken, geen fout, geen tweede pop', (tester) async {
    await pumpApp(tester);
    await startChannel(tester);
    await tapX(tester);
    opening.next.complete(null);
    await settle(tester);
    expect(service.calls, isEmpty);
    expect(find.text('zender'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R7 zonder X, PlaybackInfo faalt: dialoog dicht en melding, pagina blijft', (tester) async {
    await pumpApp(tester);
    await startChannel(tester);
    opening.next.complete(null);
    await settle(tester);
    expect(find.byIcon(IconsaxPlusLinear.close_square), findsNothing);
    expect(find.text('zender'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('R8 film: loadPlaybackItem speelt nog normaal (regressie isStopped en verplaatste startpositie)',
      (tester) async {
    await pumpApp(tester);
    final film = DirectPlaybackModel(item: channel('film'), media: const Media(url: 'http://jf/film'));
    final loading = container.read(videoPlayerProvider.notifier).loadPlaybackItem(film, Duration.zero);
    await settle(tester);
    expect(await loading, isTrue);
    expect(player.calls, containsAllInOrder(['load:http://jf/film', 'audioTrack', 'play']));
    expect(container.read(playBackModel), same(film));
    expect(container.read(mediaPlaybackProvider).state, VideoPlayerState.fullScreen);
  });

  testWidgets('R9 film: stop tijdens loadVideo blijft als voorheen, wordt niet onthouden', (tester) async {
    await pumpApp(tester);
    final film = DirectPlaybackModel(item: channel('film'), media: const Media(url: 'http://jf/film'));
    final held = Completer<void>();
    player.holdLoad = held;
    final loading = container.read(videoPlayerProvider.notifier).loadPlaybackItem(film, Duration.zero);
    await settle(tester);
    await container.read(videoPlayerProvider).stop();
    held.complete();
    await settle(tester);
    expect(await loading, isTrue);
    expect(player.calls, contains('play'));
    expect(container.read(playBackModel), same(film));
  });

  testWidgets('R10 X tijdens setAudioTrack terwijl de deferred stop niets meer te doen heeft: 1 Stopped', (tester) async {
    await pumpApp(tester);
    final held = Completer<void>();
    player.holdLoad = held;
    player.holdAudioTrack = Completer();
    await startChannel(tester);
    opening.next.complete(tv('new'));
    await settle(tester);
    await tapX(tester); // tijdens loadVideo
    held.complete();
    await settle(tester);
    player.holdAudioTrack!.complete();
    await settle(tester);
    expect(service.calls, ['stopped:new']);
    expect(player.calls.where((c) => c == 'stop').length, greaterThanOrEqualTo(1));
    expect(player.calls, isNot(contains('play')));
  });

  /// De wrapper hoort bij de echte zone (setup in runAsync): stop() wacht daar op een stream die pump niet verder zet.
  Future<void> realTick(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await settle(tester, 100);
    }
  }

  void mockWakelock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (message) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  }

  testWidgets('R11 zappen via loadTVChannel met de echte loadPlaybackItem: oud dicht, nieuw speelt', (tester) async {
    mockWakelock();
    await pumpApp(tester);
    await startChannel(tester);
    opening.next.complete(tv('old'));
    await settle(tester);
    expect(player.calls, contains('open'));

    opening.next = Completer()..complete(tv('next'));
    unawaited(container.read(playbackModelHelper).loadTVChannel(channel('next')));
    await settle(tester);
    await realTick(tester);

    expect((container.read(playBackModel) as TvPlaybackModel).liveStreamId, 'next');
    expect(player.calls, containsAllInOrder(['load:http://jf/old', 'load:http://jf/next', 'audioTrack', 'play']));
    expect(service.calls.indexOf('stopped:old'), lessThan(service.calls.indexOf('playing:next')));
    expect(service.calls, isNot(contains('stopped:next')));

    unawaited(container.read(videoPlayerProvider).stop());
    await settle(tester);
    await realTick(tester);
    expect(service.calls, contains('stopped:next'));
  });

  testWidgets('R13 controle: zonder X laadt de zender ook na het stoppen van het vorige item', (tester) async {
    mockWakelock();
    await pumpApp(tester);
    container.read(playBackModel.notifier).state = tv('old');
    await startChannel(tester);
    opening.next.complete(tv('new'));
    await settle(tester);
    await realTick(tester);

    expect(player.calls, containsAllInOrder(['load:http://jf/new', 'play', 'open']));
    expect(service.calls, ['stopped:old', 'playing:new']);
    expect((container.read(playBackModel) as TvPlaybackModel).liveStreamId, 'new');

    unawaited(container.read(videoPlayerProvider).stop());
    await settle(tester);
    await realTick(tester);
  });

  testWidgets('R14 X terwijl het vorige item stopt, en stop() keert echt terug: niets laadt, stream dicht', (tester) async {
    mockWakelock();
    await pumpApp(tester);
    container.read(playBackModel.notifier).state = tv('old');
    service.holdStop = Completer();
    await startChannel(tester);
    opening.next.complete(tv('new'));
    await tester.pump();
    expect(service.calls, ['stopped:old']);

    await tapX(tester);
    service.holdStop!.complete();
    await settle(tester);
    await realTick(tester);

    expect(service.calls, ['stopped:old', 'stopped:new']);
    expect(player.calls.where((c) => c.startsWith('load:')), isEmpty, reason: '${player.calls}');
    expect(player.calls, isNot(contains('play')));
    expect(player.calls, isNot(contains('open')));
    expect(container.read(playBackModel), isNull);
    expect(container.read(mediaPlaybackProvider).state, isNot(VideoPlayerState.fullScreen));
    expect(find.text('zender'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('R15 na R14 start een nieuwe zender nog normaal, en stop werkt', (tester) async {
    mockWakelock();
    await pumpApp(tester);
    container.read(playBackModel.notifier).state = tv('old');
    service.holdStop = Completer();
    await startChannel(tester);
    opening.next.complete(tv('first'));
    await tester.pump();
    await tapX(tester);
    service.holdStop!.complete();
    service.holdStop = null;
    await settle(tester);
    await realTick(tester);

    opening.next = Completer();
    await startChannel(tester);
    opening.next.complete(tv('second'));
    await settle(tester);
    await realTick(tester);

    expect(player.calls, containsAllInOrder(['load:http://jf/second', 'play', 'open']));
    expect((container.read(playBackModel) as TvPlaybackModel).liveStreamId, 'second');
    unawaited(container.read(videoPlayerProvider).stop());
    await settle(tester);
    await realTick(tester);
    expect(service.calls.where((c) => c == 'stopped:second').length, 1);
    expect(container.read(playBackModel), isNull);
  });
}
