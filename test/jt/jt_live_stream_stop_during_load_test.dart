import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/incognito_mode_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

final _refProvider = Provider<Ref>((ref) => ref);

class _Service implements JellyService {
  final List<String> calls = [];
  bool failStop = false;
  chopper.Response<void> get _ok => chopper.Response(http.Response('', 204), null);

  @override
  Future<chopper.Response> sessionsPlayingStoppedPost({required PlaybackStopInfo? body}) async {
    calls.add('stopped:${body?.liveStreamId}');
    if (failStop) throw Exception('offline');
    return _ok;
  }

  @override
  Future<chopper.Response> liveStreamsClosePost({required String liveStreamId}) async {
    calls.add('close:$liveStreamId');
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

class _SlowPlayer extends BasePlayer {
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
  Future<void> open(BuildContext context) async {}
  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) =>
      Future.delayed(const Duration(milliseconds: 300));
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> playOrPause() async {}
  @override
  Future<void> loop(bool loop) async {}
  @override
  Future<Uint8List?> takeScreenshot() async => null;
  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => -1;
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async => -1;
}

void main() {
  late _Service service;
  late ProviderContainer container;
  late MediaControlsWrapper wrapper;
  late Ref ref;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TvPlaybackModel.resetClosedLiveStreams();
    service = _Service();
    container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _Api(service)),
      incognitoProvider.overrideWith((ref) => false),
    ]);
    addTearDown(container.dispose);
    ref = container.read(_refProvider);
    wrapper = MediaControlsWrapper(ref: ref);
    // Windows hosts fail on the SMTC setup after _player is set, which is all this needs.
    try {
      await wrapper.setup(_SlowPlayer());
    } catch (_) {}
  });

  TvPlaybackModel tv(String stream) {
    final channel = ChannelModel.fromBaseDto(BaseItemDto(id: stream, name: stream, type: BaseItemKind.tvchannel), ref);
    return TvPlaybackModel(
      channel: channel,
      item: channel,
      playbackInfo: PlaybackInfoResponse(
        playSessionId: 'session-$stream',
        mediaSources: [MediaSourceInfo(id: 'source', liveStreamId: stream)],
      ),
    );
  }

  /// What VideoPlayerNotifier.loadPlaybackItem does: stop, set the model, load.
  Future<void> startLoading(TvPlaybackModel next, {void Function()? before}) async {
    await wrapper.stopBeforeLoad();
    before?.call();
    container.read(playBackModel.notifier).state = next;
  }

  test('Back or Home while a channel loads stops that channel', () async {
    final next = tv('new');
    await startLoading(next);
    final loading = wrapper.loadVideo(next, Duration.zero, true);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    wrapper.onStop();
    await loading;

    expect(service.calls, ['stopped:new']);
    expect(container.read(playBackModel), isNull);
  });

  test('Back or Home between the old stop and the load counts as well', () async {
    final next = tv('new');
    await startLoading(next, before: wrapper.onStop);
    await wrapper.loadVideo(next, Duration.zero, true);

    expect(service.calls, ['stopped:new']);
  });

  test('a failed stop still closes a channel stopped while loading', () async {
    service.failStop = true;
    final next = tv('new');
    await startLoading(next);
    final loading = wrapper.loadVideo(next, Duration.zero, true);

    wrapper.onStop();
    await loading;

    expect(service.calls, ['stopped:new', 'close:new']);
  });

  test('a channel that loads undisturbed keeps playing', () async {
    final next = tv('new');
    await startLoading(next);
    await wrapper.loadVideo(next, Duration.zero, true);

    expect(service.calls, isEmpty);
    expect(container.read(playBackModel), same(next));

    await wrapper.stop();
    expect(service.calls, ['stopped:new']);
  });

  test('a stop without a load in sight is not kept for the next channel', () async {
    await wrapper.stop();
    await wrapper.stop();

    final next = tv('new');
    await startLoading(next);
    await wrapper.loadVideo(next, Duration.zero, true);

    expect(service.calls, isEmpty);
  });
}
