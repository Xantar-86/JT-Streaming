import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/profiles/web_profile.dart';
import 'package:fladder/providers/video_player_provider.dart';

final videoProfileProvider = StateProvider.autoDispose<DeviceProfile>((ref) =>
    defaultProfile(ref.read(videoPlayerProvider.select((value) => value.backend)) ?? PlayerOptions.platformDefaults));

// JT-HOOK: native-no-avi - de ExoPlayer van Android TV leest van een AVI alleen het eerste RIFF-deel,
// en een AVI boven 4 GB bestaat uit meerdere delen. Het minteken is een uitsluitlijst bij Jellyfin:
// alle andere containers blijven direct spelen, een AVI gaat als HLS via de server.
DeviceProfile defaultProfile(PlayerOptions player) => kIsWeb
    ? webProfile
    : DeviceProfile(
        maxStreamingBitrate: 120000000,
        maxStaticBitrate: 120000000,
        musicStreamingTranscodingBitrate: 384000,
        directPlayProfiles: [
          DirectPlayProfile(
            container: player == PlayerOptions.nativePlayer ? '-avi' : null,
            type: DlnaProfileType.video,
          ),
          const DirectPlayProfile(
            type: DlnaProfileType.audio,
          )
        ],
        transcodingProfiles: const [
          TranscodingProfile(
            audioCodec: 'aac,mp3,mp2',
            container: 'ts',
            maxAudioChannels: '2',
            protocol: MediaStreamProtocol.hls,
            type: DlnaProfileType.video,
            videoCodec: 'h264',
          ),
        ],
        containerProfiles: const [],
        subtitleProfiles: const [
          SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'ass', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'ssa', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'pgssub', method: SubtitleDeliveryMethod.$external),
        ],
      );

// JT-HOOK: native-no-avi - een download zonder transcoderen blijft het originele bestand, dus ook een
// AVI. Met het afspeelprofiel zou Jellyfin hier HLS aanbieden, en dan komt master.m3u8 in het .avi-bestand.
final DeviceProfile jtDownloadProfile = defaultProfile(PlayerOptions.libMPV);
