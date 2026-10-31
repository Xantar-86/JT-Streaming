import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

final _refProvider = Provider<Ref>((ref) => ref);

class _Service implements JellyService {
  final List<String> calls = [];
  bool failStop = false;
  Completer<void>? holdStop;
  chopper.Response<void> get _ok => chopper.Response(http.Response('', 204), null);

  @override
  Future<chopper.Response> sessionsPlayingStoppedPost({required PlaybackStopInfo? body}) async {
    calls.add('stopped:${body?.liveStreamId}');
    await holdStop?.future;
    if (failStop) throw Exception('offline');
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

/// Stands in for the server part only, the X and everything after it are the real code.
class _Helper extends PlaybackModelHelper {
  const _Helper(this.opening, {required super.ref});
  final Future<PlaybackModel?> opening;

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
      opening;
}

class _Player extends BasePlayer {
  final List<String> calls = [];
  Completer<void>? holdLoad;
  Completer<void>? holdAudioTrack;
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
    calls.add('load');
    await holdLoad?.future;
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
  late Completer<PlaybackModel?> opening;
  late ProviderContainer container;

  ChannelModel channel(String id) => ChannelModel.fromBaseDto(
        BaseItemDto(id: id, name: id, type: BaseItemKind.tvchannel),
        container.read(_refProvider),
      );

  TvPlaybackModel tv(String stream) {
    final item = channel(stream);
    return TvPlaybackModel(
      channel: item,
      item: item,
      media: const Media(url: 'http://jf/stream'),
      playbackInfo: PlaybackInfoResponse(
        playSessionId: 'session-$stream',
        mediaSources: [MediaSourceInfo(id: 'source', liveStreamId: stream)],
      ),
    );
  }

  /// Pumps a page with a button that plays a channel.
  Future<void> pumpApp(WidgetTester tester) async {
    TvPlaybackModel.resetClosedLiveStreams();
    service = _Service();
    player = _Player();
    opening = Completer();
    container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _Api(service)),
      incognitoProvider.overrideWith((ref) => false),
      liveTvProvider.overrideWith(_LiveTv.new),
      videoPlayerProvider.overrideWith((ref) => VideoPlayerNotifier(ref)),
      playbackModelHelper.overrideWith((ref) => _Helper(opening.future, ref: ref)),
    ]);
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      // Windows hosts fail on the SMTC setup after _player is set, which is all this needs.
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
                onPressed: () => channel('new').play(context, ref),
                child: const Text('zender'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> startChannel(WidgetTester tester) async {
    await tester.tap(find.text('zender'));
    await tester.pump();
  }

  Future<void> tapX(WidgetTester tester) async {
    await tester.tap(find.byIcon(IconsaxPlusLinear.close_square));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The stream is gone, nothing plays, no player came up and the app stayed where it was.
  void expectAbandoned(WidgetTester tester, {List<String> calls = const ['stopped:new']}) {
    expect(service.calls, calls);
    expect(container.read(playBackModel), isNull);
    expect(player.calls, isNot(contains('open')));
    expect(player.calls, isNot(contains('play')));
    expect(container.read(mediaPlaybackProvider).state, isNot(VideoPlayerState.fullScreen));
    expect(find.text('zender'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  }

  testWidgets('X before PlaybackInfo answered closes the stream it opens, nothing gets loaded', (tester) async {
    await pumpApp(tester);
    await startChannel(tester);

    await tapX(tester);
    expect(service.calls, isEmpty);

    opening.complete(tv('new'));
    await settle(tester);

    expectAbandoned(tester);
    expect(player.calls, isNot(contains('load')));
  });

  testWidgets('X after PlaybackInfo, while the previous item stops', (tester) async {
    await pumpApp(tester);
    container.read(playBackModel.notifier).state = tv('old');
    service.holdStop = Completer();
    await startChannel(tester);

    opening.complete(tv('new'));
    await tester.pump();
    expect(service.calls, ['stopped:old']);

    await tapX(tester);
    service.holdStop!.complete();
    await settle(tester);

    expectAbandoned(tester, calls: ['stopped:old', 'stopped:new']);
    expect(player.calls, isNot(contains('load')));
  });

  testWidgets('X during loadVideo closes right away and stops the player once it loaded', (tester) async {
    await pumpApp(tester);
    player.holdLoad = Completer();
    await startChannel(tester);

    opening.complete(tv('new'));
    await settle(tester);
    expect(player.calls, contains('load'));

    await tapX(tester);
    expect(service.calls, ['stopped:new']);

    player.holdLoad!.complete();
    await settle(tester);

    expectAbandoned(tester);
    expect(player.calls, contains('stop'));
  });

  testWidgets('X during the wait on setAudioTrack stops the sound right away', (tester) async {
    await pumpApp(tester);
    player.holdAudioTrack = Completer();
    await startChannel(tester);

    opening.complete(tv('new'));
    await settle(tester);
    expect(player.calls, contains('audioTrack'));

    await tapX(tester);
    expect(service.calls, ['stopped:new']);
    expect(player.calls, contains('stop'));

    player.holdAudioTrack!.complete();
    await settle(tester);

    expectAbandoned(tester);
  });

  testWidgets('X with a stop that fails falls back on Close', (tester) async {
    await pumpApp(tester);
    service.failStop = true;
    player.holdAudioTrack = Completer();
    await startChannel(tester);

    opening.complete(tv('new'));
    await settle(tester);

    await tapX(tester);
    await settle(tester);
    player.holdAudioTrack!.complete();
    await settle(tester);

    expectAbandoned(tester, calls: ['stopped:new', 'close:new']);
  });

  testWidgets('no X: the channel plays and its stream stays open', (tester) async {
    await pumpApp(tester);
    await startChannel(tester);

    opening.complete(tv('new'));
    await settle(tester);

    expect(player.calls, containsAllInOrder(['load', 'audioTrack', 'play', 'open']));
    expect(service.calls, isNot(contains('stopped:new')));
    expect(container.read(playBackModel), isNotNull);

    unawaited(container.read(videoPlayerProvider).stop());
    await settle(tester);
    expect(service.calls, contains('stopped:new'));
  });
}
