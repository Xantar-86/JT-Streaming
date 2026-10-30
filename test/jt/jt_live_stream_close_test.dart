import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';

final _refProvider = Provider<Ref>((ref) => ref);

class _FakeService implements JellyService {
  final List<String> calls = [];
  final List<PlaybackStopInfo?> stops = [];
  bool failStop = false;
  Completer<void>? holdStop;

  chopper.Response<void> get _ok => chopper.Response(http.Response('', 204), null);

  @override
  Future<chopper.Response> sessionsPlayingStoppedPost({required PlaybackStopInfo? body}) async {
    calls.add('stopped');
    stops.add(body);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeService service;
  late ProviderContainer container;
  late Ref ref;

  ChannelModel channelNamed(String id) => ChannelModel.fromBaseDto(
        BaseItemDto(id: id, name: id, type: BaseItemKind.tvchannel),
        ref,
      );

  TvPlaybackModel model({String? liveStreamId = 'stream-1'}) {
    final channel = channelNamed('channel-1');
    return TvPlaybackModel(
      channel: channel,
      item: channel,
      playbackInfo: PlaybackInfoResponse(
        playSessionId: 'session-1',
        mediaSources: [MediaSourceInfo(id: 'source-1', liveStreamId: liveStreamId)],
      ),
    );
  }

  setUp(() {
    TvPlaybackModel.resetClosedLiveStreams();
    service = _FakeService();
    container = ProviderContainer(overrides: [
      jellyApiProvider.overrideWith(() => _StubJellyApi(service)),
      videoPlayerProvider.overrideWith((ref) => _FakePlayer(ref, service)),
    ]);
    addTearDown(container.dispose);
    ref = container.read(_refProvider);
  });

  test('stopping reports the live stream and then closes it', () async {
    await model().playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped', 'close:stream-1']);
    final stop = service.stops.single!;
    expect(stop.liveStreamId, 'stream-1');
    expect(stop.playSessionId, 'session-1');
    expect(stop.itemId, 'channel-1');
    expect(stop.mediaSourceId, 'source-1');
  });

  test('the zap and the stop after it close a stream once, also from a copy', () async {
    final tv = model();
    await tv.closeLiveStream(ref);
    await tv.copyWith(position: const Duration(seconds: 5)).playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped', 'close:stream-1']);
  });

  test('closing twice at once sends one close', () async {
    service.holdStop = Completer();
    final tv = model();
    final first = tv.closeLiveStream(ref);
    final second = tv.closeLiveStream(ref);
    service.holdStop!.complete();
    await Future.wait([first, second]);

    expect(service.calls, ['stopped', 'close:stream-1']);
  });

  test('a failing stop report still closes the stream', () async {
    service.failStop = true;
    await model().playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped', 'close:stream-1']);
  });

  test('a closed stream is finished before the caller continues', () async {
    service.holdStop = Completer();
    var closed = false;
    final closing = model().closeLiveStream(ref).then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);

    expect(closed, isFalse);
    expect(service.calls, ['stopped']);

    service.holdStop!.complete();
    await closing;
    expect(service.calls, ['stopped', 'close:stream-1']);
  });

  test('without a live stream id only the stop is reported', () async {
    await model(liveStreamId: null).playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped']);
  });

  group('zapping', () {
    final gates = <String, Completer<void>>{};
    late _ZapHelper helper;

    setUp(() {
      gates.clear();
      helper = _ZapHelper(ref, (channel) async {
        service.calls.add('open:${channel.id}');
        await gates[channel.id]?.future;
        return model(liveStreamId: channel.id);
      });
      container.read(playBackModel.notifier).state = model(liveStreamId: 'old');
    });

    test('closes the running stream before the new one opens', () async {
      await helper.loadTVChannel(channelNamed('new'));

      expect(service.calls, ['stopped', 'close:old', 'open:new', 'load:new']);
    });

    test('never opens two streams at once and only loads the last channel', () async {
      gates['b'] = Completer();
      final first = helper.loadTVChannel(channelNamed('b'));
      await Future<void>.delayed(Duration.zero);
      expect(service.calls.last, 'open:b');

      helper.loadTVChannel(channelNamed('c'));
      final last = helper.loadTVChannel(channelNamed('d'));
      await Future<void>.delayed(Duration.zero);
      expect(service.calls.last, 'open:b');

      gates['b']!.complete();
      await Future.wait([first, last]);

      expect(service.calls, [
        'stopped',
        'close:old',
        'open:b',
        'stopped',
        'close:b',
        'open:d',
        'load:d',
      ]);
    });

    test('a stop while the stream opens closes that stream', () async {
      gates['late'] = Completer();
      final zap = helper.loadTVChannel(channelNamed('late'));
      await Future<void>.delayed(Duration.zero);
      container.read(playBackModel.notifier).state = null;
      gates['late']!.complete();
      await zap;

      expect(service.calls, ['stopped', 'close:old', 'open:late', 'stopped', 'close:late']);
    });
  });
}

class _FakePlayer extends VideoPlayerNotifier {
  _FakePlayer(super.ref, this.service);

  final _FakeService service;

  @override
  Future<bool> loadPlaybackItem(PlaybackModel model, Duration startPosition) async {
    service.calls.add('load:${(model as TvPlaybackModel).liveStreamId}');
    ref.read(playBackModel.notifier).state = model;
    return true;
  }
}

/// Stands in for the server call only: like the real model creation it releases the running stream first.
class _ZapHelper extends PlaybackModelHelper {
  const _ZapHelper(Ref ref, this.open) : super(ref: ref);

  final Future<PlaybackModel?> Function(ChannelModel channel) open;

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
  }) async {
    await ref.read(videoPlayerProvider).releaseLiveStream();
    return open(item as ChannelModel);
  }
}

class _StubJellyApi extends JellyApi {
  _StubJellyApi(this.service);

  final JellyService service;

  @override
  JellyService build() => service;
}
