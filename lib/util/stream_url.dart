import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/providers/api_provider.dart';

/// Builds the static direct stream url for [mediaSource] of the item [itemId].
///
/// The path always uses the item id (`/Videos/{itemId}/stream`), the media source is selected
/// with the `mediaSourceId` query parameter. This matches jellyfin-web and is required for
/// live tv, where the media source id (`native_...`) is not a valid item id.
Uri? directStreamUri(
  String? baseUrl, {
  required String itemId,
  required MediaSourceInfo mediaSource,
  String? token,
}) {
  if (baseUrl == null || baseUrl.isEmpty) return null;
  final Map<String, String?> directOptions = {
    'Static': 'true',
    'mediaSourceId': mediaSource.id,
    'api_key': token,
  };

  if (mediaSource.eTag != null) {
    directOptions['Tag'] = mediaSource.eTag;
  }

  if (mediaSource.liveStreamId != null) {
    directOptions['LiveStreamId'] = mediaSource.liveStreamId;
  }

  return buildServerUriFromBase(
    baseUrl,
    pathSegments: ['Videos', itemId, 'stream'],
    queryParameters: directOptions,
  );
}

/// Resolves a server relative url (like `TranscodingUrl`) against [baseUrl].
/// Absolute urls are rejected so playback never leaves the Jellyfin server.
Uri? serverRelativeUri(String? baseUrl, String? relativeUrl) {
  if (baseUrl == null || baseUrl.isEmpty || relativeUrl == null || relativeUrl.trim().isEmpty) return null;
  final relative = Uri.tryParse(relativeUrl.trim());
  if (relative == null || relative.hasScheme || relative.hasAuthority) return null;
  return buildServerUriFromBase(baseUrl, relativeUrl: relativeUrl);
}

enum PlaybackUrlType { liveTv, directStream, transcode }

class PlaybackUrl {
  final PlaybackUrlType type;
  final String url;

  const PlaybackUrl(this.type, this.url);

  @override
  String toString() => 'PlaybackUrl(type: $type, url: $url)';
}

/// Selects how and from which url [mediaSource] of the item [itemId] is played.
///
/// [MediaSourceInfo.path] is intentionally never used: for live tv it points to the tuner (often an
/// address only reachable by the server) and for remote (strm) items to the provider. Every url goes
/// through the Jellyfin server, like jellyfin-web.
///
/// Live tv uses the HLS `TranscodingUrl` on players without MPEG-TS support (web) and the direct stream
/// url on the other players. Without a usable url it falls back to the regular direct stream/transcode
/// selection.
PlaybackUrl? selectPlaybackUrl(
  String? baseUrl, {
  required String itemId,
  required MediaSourceInfo mediaSource,
  String? token,
  bool isLiveTv = false,
  bool playerSupportsMpegTs = true,
}) {
  Uri? directStream() => directStreamUri(baseUrl, itemId: itemId, mediaSource: mediaSource, token: token);

  if (isLiveTv) {
    final liveTvUri = playerSupportsMpegTs ? directStream() : serverRelativeUri(baseUrl, mediaSource.transcodingUrl);
    if (liveTvUri != null) return PlaybackUrl(PlaybackUrlType.liveTv, liveTvUri.toString());
  }

  if ((mediaSource.supportsDirectStream ?? false) || (mediaSource.supportsDirectPlay ?? false)) {
    final uri = directStream();
    return uri == null ? null : PlaybackUrl(PlaybackUrlType.directStream, uri.toString());
  } else if ((mediaSource.supportsTranscoding ?? false) && mediaSource.transcodingUrl != null) {
    final uri = serverRelativeUri(baseUrl, mediaSource.transcodingUrl);
    return uri == null ? null : PlaybackUrl(PlaybackUrlType.transcode, uri.toString());
  }
  return null;
}
