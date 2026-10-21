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
        path: 'http://172.18.0.43:8096/LiveTv/LiveStreamFiles/0123/stream.ts',
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
}
