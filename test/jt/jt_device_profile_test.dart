import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/profiles/default_profile.dart';

String? _videoContainer(PlayerOptions player) => defaultProfile(player)
    .directPlayProfiles!
    .firstWhere((profile) => profile.type == DlnaProfileType.video)
    .container;

void main() {
  test('de native speler speelt geen AVI direct, de rest blijft ongemoeid', () {
    expect(_videoContainer(PlayerOptions.nativePlayer), '-avi');
  });

  test('mpv en mdk spelen AVI wel, daar blijft alles direct', () {
    expect(_videoContainer(PlayerOptions.libMPV), isNull);
    expect(_videoContainer(PlayerOptions.libMDK), isNull);
  });

  test('audio en de transcodeerroute veranderen niet', () {
    final profile = defaultProfile(PlayerOptions.nativePlayer);
    expect(profile.directPlayProfiles!.firstWhere((p) => p.type == DlnaProfileType.audio).container, isNull);
    final transcode = profile.transcodingProfiles!.single;
    expect(transcode.protocol, MediaStreamProtocol.hls);
    expect(transcode.videoCodec, 'h264');
    expect(transcode.audioCodec, contains('mp3'));
  });

  test('een download blijft het originele bestand: geen AVI-uitsluiting, wel dezelfde rest', () {
    final video = jtDownloadProfile.directPlayProfiles!.firstWhere((p) => p.type == DlnaProfileType.video);
    expect(video.container, isNull);
    expect(
      jtDownloadProfile.toJson(),
      defaultProfile(PlayerOptions.libMPV).toJson(),
      reason: 'zelfde vraag als jt.6.7, waarop de server DirectPlay=True antwoordt',
    );
  });
}
