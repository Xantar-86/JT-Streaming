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
