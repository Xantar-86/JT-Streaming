import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/util/stream_url.dart';

const baseUrl = 'https://jellyfin.example.com';
const token = 'test-token';

/// The url as built before this change (media source id in the path).
String legacyDirectStreamUrl(String baseUrl, MediaSourceInfo mediaSource, String? token) {
  final Map<String, String?> directOptions = {
    'Static': 'true',
    'mediaSourceId': mediaSource.id,
    'ApiKey': token,
  };
  if (mediaSource.eTag != null) directOptions['Tag'] = mediaSource.eTag;
  if (mediaSource.liveStreamId != null) directOptions['LiveStreamId'] = mediaSource.liveStreamId;
  return buildServerUriFromBase(
    baseUrl,
    pathSegments: ['Videos', mediaSource.id ?? '', 'stream'],
    queryParameters: directOptions,
  ).toString();
}

void main() {
  group('directStreamUri', () {
    test('live tv uses the channel id in the path and passes mediaSourceId/LiveStreamId as query', () {
      const channelId = 'e3b08cb7a1b2c3d4e5f60718293a4b5c';
      const mediaSourceId = 'native_bb53ee23f00d4a5b8c9d0e1f2a3b4c5d_e3b08cb7a1b2c3d4e5f60718293a4b5c';
      const liveStreamId = '0123456789abcdef0123456789abcdef_native_bb53ee23';
      const mediaSource = MediaSourceInfo(
        id: mediaSourceId,
        liveStreamId: liveStreamId,
        path: 'http://192.0.2.43:8096/LiveTv/LiveStreamFiles/0123/stream.ts',
      );

      final uri = directStreamUri(baseUrl, itemId: channelId, mediaSource: mediaSource, token: token)!;

      expect(uri.pathSegments, ['Videos', channelId, 'stream']);
      expect(uri.path, isNot(contains('native_')));
      expect(uri.queryParameters['mediaSourceId'], mediaSourceId);
      expect(uri.queryParameters['LiveStreamId'], liveStreamId);
      expect(uri.queryParameters['Static'], 'true');
      expect(uri.queryParameters['ApiKey'], token);
      expect(uri.host, 'jellyfin.example.com');
      expect(uri.toString(), isNot(mediaSource.path));
    });

    test('regular movie url is byte-identical to the previous url', () {
      const movieId = '3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c';
      const mediaSource = MediaSourceInfo(
        id: movieId,
        eTag: 'abcdef0123456789',
        path: '/media/movies/Some Movie (2020)/Some Movie (2020).mkv',
      );

      final url = directStreamUri(baseUrl, itemId: movieId, mediaSource: mediaSource, token: token).toString();

      expect(url, legacyDirectStreamUrl(baseUrl, mediaSource, token));
      expect(
        url,
        'https://jellyfin.example.com/Videos/3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c/stream'
        '?Static=true&mediaSourceId=3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c&ApiKey=test-token&Tag=abcdef0123456789',
      );
    });

    test('keeps a base url sub path', () {
      const mediaSource = MediaSourceInfo(id: 'abc');
      final url = directStreamUri('https://example.com/jellyfin/', itemId: 'abc', mediaSource: mediaSource).toString();
      expect(url, 'https://example.com/jellyfin/Videos/abc/stream?Static=true&mediaSourceId=abc');
    });

    test('returns null without a server url', () {
      const mediaSource = MediaSourceInfo(id: 'abc');
      expect(directStreamUri(null, itemId: 'abc', mediaSource: mediaSource), isNull);
      expect(directStreamUri('', itemId: 'abc', mediaSource: mediaSource), isNull);
    });
  });

  group('selectPlaybackUrl never plays MediaSource.Path', () {
    const channelId = 'e3b08cb7a1b2c3d4e5f60718293a4b5c';
    const liveMediaSourceId = 'native_bb53ee23f00d4a5b8c9d0e1f2a3b4c5d_e3b08cb7a1b2c3d4e5f60718293a4b5c';
    const liveStreamId = '0123456789abcdef0123456789abcdef_native_bb53ee23';
    const tunerPath = 'http://192.0.2.43:8096/LiveTv/LiveStreamFiles/0123456789abcdef/stream.ts';
    const transcodingUrl = '/videos/$channelId/master.m3u8?DeviceId=abc&MediaSourceId=$liveMediaSourceId'
        '&VideoCodec=h264&AudioCodec=aac&PlaySessionId=42&api_key=$token&LiveStreamId=$liveStreamId'
        '&TranscodingMaxAudioChannels=2&SegmentContainer=ts';

    // Live tv as returned with the web profile: no direct stream, server HLS available.
    const liveWebSource = MediaSourceInfo(
      id: liveMediaSourceId,
      liveStreamId: liveStreamId,
      path: tunerPath,
      protocol: MediaProtocol.http,
      isRemote: false,
      isInfiniteStream: true,
      supportsDirectPlay: false,
      supportsDirectStream: false,
      supportsTranscoding: true,
      transcodingUrl: transcodingUrl,
    );

    // Live tv as returned without a device profile (desktop): tuner flags, no TranscodingUrl.
    const liveDesktopSource = MediaSourceInfo(
      id: liveMediaSourceId,
      liveStreamId: liveStreamId,
      path: tunerPath,
      protocol: MediaProtocol.http,
      isInfiniteStream: true,
      supportsDirectPlay: true,
      supportsDirectStream: true,
      supportsTranscoding: true,
    );

    test('(a) live tv on web uses the server master.m3u8', () {
      final result = selectPlaybackUrl(
        baseUrl,
        itemId: channelId,
        mediaSource: liveWebSource,
        token: token,
        isLiveTv: true,
        playerSupportsMpegTs: false,
      )!;
      final uri = Uri.parse(result.url);

      expect(result.type, PlaybackUrlType.liveTv);
      expect(result.url, startsWith('$baseUrl/'));
      expect(uri.path, '/videos/$channelId/master.m3u8');
      expect(uri.queryParameters['LiveStreamId'], liveStreamId);
      expect(result.url, isNot(liveWebSource.path));
      expect(result.url, isNot(contains('192.0.2.43')));
    });

    test('(a) live tv on desktop uses the server direct stream with channel id', () {
      final result = selectPlaybackUrl(
        baseUrl,
        itemId: channelId,
        mediaSource: liveDesktopSource,
        token: token,
        isLiveTv: true,
        playerSupportsMpegTs: true,
      )!;
      final uri = Uri.parse(result.url);

      expect(result.type, PlaybackUrlType.liveTv);
      expect(uri.host, 'jellyfin.example.com');
      expect(uri.path, '/Videos/$channelId/stream');
      expect(uri.queryParameters['mediaSourceId'], liveMediaSourceId);
      expect(uri.queryParameters['LiveStreamId'], liveStreamId);
      expect(uri.queryParameters['Static'], 'true');
      expect(result.url, isNot(liveDesktopSource.path));
      expect(result.url, isNot(contains('192.0.2.43')));
    });

    test('(a) live tv on web without TranscodingUrl falls back to the server, never to Path', () {
      final result = selectPlaybackUrl(
        baseUrl,
        itemId: channelId,
        mediaSource: liveDesktopSource,
        token: token,
        isLiveTv: true,
        playerSupportsMpegTs: false,
      )!;

      expect(result.type, PlaybackUrlType.directStream);
      expect(Uri.parse(result.url).path, '/Videos/$channelId/stream');
      expect(result.url, isNot(liveDesktopSource.path));
    });

    test('(a) live tv rejects an absolute TranscodingUrl', () {
      const source = MediaSourceInfo(
        id: liveMediaSourceId,
        path: tunerPath,
        supportsTranscoding: true,
        transcodingUrl: 'http://192.0.2.43:8096/videos/x/master.m3u8',
      );
      final result = selectPlaybackUrl(
        baseUrl,
        itemId: channelId,
        mediaSource: source,
        isLiveTv: true,
        playerSupportsMpegTs: false,
      );
      expect(result, isNull);
    });

    test('(b) strm movie (Protocol=Http, IsRemote) is streamed through the server', () {
      const movieId = '7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a29';
      const providerPath = 'http://provider.example/movie/user/pass/123456.mkv';
      const strmSource = MediaSourceInfo(
        id: movieId,
        path: providerPath,
        protocol: MediaProtocol.http,
        isRemote: true,
        supportsDirectPlay: true,
        supportsDirectStream: true,
        supportsTranscoding: true,
      );

      for (final supportsMpegTs in [true, false]) {
        final result = selectPlaybackUrl(
          baseUrl,
          itemId: movieId,
          mediaSource: strmSource,
          token: token,
          playerSupportsMpegTs: supportsMpegTs,
        )!;

        expect(result.type, PlaybackUrlType.directStream);
        expect(result.url, startsWith('$baseUrl/Videos/$movieId/stream?'));
        expect(result.url, isNot(contains('provider.example')));
        expect(result.url, isNot(strmSource.path));
      }
    });

    test('(b) strm movie that needs transcoding uses the server TranscodingUrl', () {
      const movieId = '7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a29';
      const strmSource = MediaSourceInfo(
        id: movieId,
        path: 'http://provider.example/movie/user/pass/123456.mkv',
        protocol: MediaProtocol.http,
        isRemote: true,
        supportsDirectPlay: false,
        supportsDirectStream: false,
        supportsTranscoding: true,
        transcodingUrl: '/videos/$movieId/master.m3u8?MediaSourceId=$movieId&PlaySessionId=1',
      );

      final result = selectPlaybackUrl(baseUrl, itemId: movieId, mediaSource: strmSource, token: token)!;

      expect(result.type, PlaybackUrlType.transcode);
      expect(result.url, startsWith('$baseUrl/videos/$movieId/master.m3u8?'));
      expect(result.url, isNot(contains('provider.example')));
    });

    test('(c) regular movie is byte-identical to the previous url', () {
      const movieId = '3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c';
      const fileSource = MediaSourceInfo(
        id: movieId,
        eTag: 'abcdef0123456789',
        path: '/media/movies/Some Movie (2020)/Some Movie (2020).mkv',
        protocol: MediaProtocol.file,
        supportsDirectPlay: true,
        supportsDirectStream: true,
        supportsTranscoding: true,
      );

      final direct = selectPlaybackUrl(baseUrl, itemId: movieId, mediaSource: fileSource, token: token)!;
      expect(direct.type, PlaybackUrlType.directStream);
      expect(direct.url, legacyDirectStreamUrl(baseUrl, fileSource, token));

      const transcodeUrl = '/videos/$movieId/master.m3u8?MediaSourceId=$movieId&PlaySessionId=1&api_key=$token';
      const transcodeSource = MediaSourceInfo(
        id: movieId,
        path: '/media/movies/Some Movie (2020)/Some Movie (2020).mkv',
        supportsDirectPlay: false,
        supportsDirectStream: false,
        supportsTranscoding: true,
        transcodingUrl: transcodeUrl,
      );
      final transcode = selectPlaybackUrl(baseUrl, itemId: movieId, mediaSource: transcodeSource, token: token)!;
      expect(transcode.type, PlaybackUrlType.transcode);
      expect(transcode.url, buildServerUriFromBase(baseUrl, relativeUrl: transcodeUrl).toString());
    });

    test('nothing playable returns null', () {
      const source = MediaSourceInfo(id: 'abc', path: 'http://provider.example/x.ts');
      expect(selectPlaybackUrl(baseUrl, itemId: 'abc', mediaSource: source), isNull);
    });
  });
}
