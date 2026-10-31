import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/incognito_mode_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';

final _refProvider = Provider<Ref>((ref) => ref);

class _FakeService implements JellyService {
  final List<String> calls = [];
  final List<PlaybackStopInfo?> stops = [];
  bool failStop = false;
  int stopStatus = 204;
  Completer<void>? holdStop;

  chopper.Response<void> get _ok => chopper.Response(http.Response('', 204), null);

  @override
  Future<chopper.Response> sessionsPlayingStoppedPost({required PlaybackStopInfo? body}) async {
    calls.add('stopped');
    stops.add(body);
    await holdStop?.future;
    if (failStop) throw Exception('offline');
    return chopper.Response(http.Response('', stopStatus), null);
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
  late bool incognito;
  final keepalive = <String>[];

  ChannelModel channelNamed(String id) => ChannelModel.fromBaseDto(
        BaseItemDto(id: id, name: id, type: BaseItemKind.tvchannel),
        ref,
      );

  TvPlaybackModel model({String? liveStreamId = 'stream-1', String? playSessionId}) {
    final channel = channelNamed('channel-1');
    return TvPlaybackModel(
      channel: channel,
      item: channel,
      playbackInfo: PlaybackInfoResponse(
        playSessionId: playSessionId ?? 'session-$liveStreamId',
        mediaSources: [MediaSourceInfo(id: 'source-1', liveStreamId: liveStreamId)],
      ),
    );
  }

  setUp(() {
    TvPlaybackModel.resetClosedLiveStreams();
    service = _FakeService();
    incognito = false;
    keepalive.clear();
    TvPlaybackModel.postKeepalive = (url, headers, body) {
      keepalive.add('$url|${headers['content-type']}|${body ?? ''}');
      return true;
    };
    container = ProviderContainer(overrides: [
      incognitoProvider.overrideWith((ref) => incognito),
      userProvider.overrideWith(_FakeUser.new),
      jellyApiProvider.overrideWith(() => _StubJellyApi(service)),
      videoPlayerProvider.overrideWith((ref) => _FakePlayer(ref, service)),
    ]);
    addTearDown(container.dispose);
    ref = container.read(_refProvider);
    container.read(serverUrlProvider.notifier).state = 'http://jf';
  });

  test('a delivered stop closes the stream on the server, an extra close would cut off another viewer', () async {
    await model().playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped']);
    final stop = service.stops.single!;
    expect(stop.liveStreamId, 'stream-1');
    expect(stop.playSessionId, 'session-stream-1');
    expect(stop.itemId, 'channel-1');
    expect(stop.mediaSourceId, 'source-1');
  });

  test('the zap and the stop after it report a stream once, also from a copy', () async {
    final tv = model();
    await tv.closeLiveStream(ref);
    await tv.copyWith(position: const Duration(seconds: 5)).playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped']);
  });

  test('a channel opened again with the same live stream id is reported again', () async {
    await model(playSessionId: 'first').closeLiveStream(ref);
    await model(playSessionId: 'second').closeLiveStream(ref);

    expect(service.calls, ['stopped', 'stopped']);
  });

  test('closing twice at once sends one stop and one close', () async {
    service.holdStop = Completer();
    service.failStop = true;
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

  test('a stop the server refused still closes the stream', () async {
    service.stopStatus = 500;
    await model().playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped', 'close:stream-1']);
  });

  test('incognito skips the stop, so the stream is closed explicitly', () async {
    incognito = true;
    await model().playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped', 'close:stream-1']);
  });

  test('a closed stream is finished before the caller continues', () async {
    service.holdStop = Completer();
    service.failStop = true;
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
    service.failStop = true;
    await model(liveStreamId: null).playbackStopped(Duration.zero, null, ref);

    expect(service.calls, ['stopped']);
  });

  group('leaving the page', () {
    test('sends the stop with both ids and no close', () {
      model().closeLiveStreamOnPageExit(ref);

      final [url, contentType, body] = keepalive.single.split('|');
      expect(url, 'http://jf/Sessions/Playing/Stopped');
      expect(contentType, 'application/json');
      expect(jsonDecode(body), allOf(containsPair('LiveStreamId', 'stream-1'), containsPair('PlaySessionId', 'session-stream-1')));
    });

    test('closes the stream in incognito, the server never gets a stop', () {
      incognito = true;
      model().closeLiveStreamOnPageExit(ref);

      expect(keepalive.single, startsWith('http://jf/LiveStreams/Close?liveStreamId=stream-1|'));
    });

    test('closes the stream when the stop could not be sent', () {
      TvPlaybackModel.postKeepalive = (url, headers, body) {
        keepalive.add(url);
        return false;
      };
      model().closeLiveStreamOnPageExit(ref);

      expect(keepalive, ['http://jf/Sessions/Playing/Stopped', 'http://jf/LiveStreams/Close?liveStreamId=stream-1']);
    });

    test('sends nothing for a stream that was already stopped', () async {
      final tv = model();
      await tv.closeLiveStream(ref);
      tv.closeLiveStreamOnPageExit(ref);

      expect(keepalive, isEmpty);
    });
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

      expect(service.calls, ['stopped', 'open:new', 'load:new']);
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

      expect(service.calls, ['stopped', 'open:b', 'stopped', 'open:d', 'load:d']);
    });

    test('a failed stop falls back to a close before the new stream opens', () async {
      service.failStop = true;
      await helper.loadTVChannel(channelNamed('new'));

      expect(service.calls, ['stopped', 'close:old', 'open:new', 'load:new']);
    });

    test('a late stream with the id of the playing one is closed, the playing one is left alone', () async {
      final playing = model(liveStreamId: 'same', playSessionId: 'playing');
      container.read(playBackModel.notifier).state = playing;

      await helper.closeAbandonedStream(Future.value(playing));
      expect(service.calls, isEmpty);

      await helper.closeAbandonedStream(Future.value(model(liveStreamId: 'same', playSessionId: 'late')));
      expect(service.calls, ['stopped']);
    });

    test('a stop while the stream opens closes that stream', () async {
      gates['late'] = Completer();
      final zap = helper.loadTVChannel(channelNamed('late'));
      await Future<void>.delayed(Duration.zero);
      container.read(playBackModel.notifier).state = null;
      gates['late']!.complete();
      await zap;

      expect(service.calls, ['stopped', 'open:late', 'stopped']);
    });
  });
}

class _FakeUser extends User {
  @override
  AccountModel? build() => AccountModel(
        name: 'forge-test',
        id: 'u1',
        avatar: '',
        lastUsed: DateTime(2026),
        credentials: CredentialsModel.internal(),
      );
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
