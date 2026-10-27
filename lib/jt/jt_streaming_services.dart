// JT-Streaming: externe streamingdiensten (vtmGO, GOPlay) in de zijbalk.
//
// Ze staan tussen de Jellyfin-bibliotheken in de lijst "Libraries", direct na
// [JtStreamingServices.insertAfterLibrary]. Bestaat die bibliotheek niet, dan
// komen ze achteraan. Klikken opent de dienst:
//  * Android (TV): de app via de intent-URI (MainActivity, kanaal [_channel]),
//    met als terugval de app gewoon starten en daarna de Play Store.
//  * Windows en web: de website in de browser.
// Ingehaakt in side_navigation_buttons.dart (JT-HOOK: sidebar-streaming).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart' as urilauncher;

import 'package:fladder/models/view_model.dart';
import 'package:fladder/theme.dart';

class JtStreamingService {
  final String id;
  final String name;
  final String logoAsset;
  final String androidIntentUri;
  final String webUrl;

  const JtStreamingService({
    required this.id,
    required this.name,
    required this.logoAsset,
    required this.androidIntentUri,
    required this.webUrl,
  });

  /// Komt nooit voor in een route, dus het item wordt nooit "geselecteerd".
  String get pathKey => 'jt-streaming-service-$id';
}

class JtStreamingServices {
  JtStreamingServices._();

  /// Naam van de Jellyfin-bibliotheek waarna de diensten komen.
  static const insertAfterLibrary = 'Apple TV+ Series';

  static const vtmGo = JtStreamingService(
    id: 'vtmgo',
    name: 'vtm GO',
    logoAsset: 'assets/jt/vtmgo.png',
    androidIntentUri: 'intent://#Intent;package=be.vmma.vtm.zenderapp;scheme=vtmgo;'
        'S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dbe.vmma.vtm.zenderapp;end;',
    webUrl: 'https://www.vtmgo.be',
  );

  static const goPlay = JtStreamingService(
    id: 'goplay',
    name: 'GOPlay',
    logoAsset: 'assets/jt/goplay.png',
    androidIntentUri: 'intent://www.goplay.be#Intent;scheme=https;package=be.goplay.app;'
        'S.browser_fallback_url=https%3A%2F%2Fplay.google.com%2Fstore%2Fapps%2Fdetails%3Fid%3Dbe.goplay.app;end',
    webUrl: 'https://www.goplay.be',
  );

  static const List<JtStreamingService> all = [vtmGo, goPlay];

  static const _channel = MethodChannel('be.jt.streaming/intent');

  /// Opent de dienst: op Android de app, elders de website.
  static Future<void> open(JtStreamingService service) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final opened = await _channel.invokeMethod<bool>('openIntentUri', {'uri': service.androidIntentUri});
        if (opened == true) return;
      } on PlatformException catch (e) {
        debugPrint('JT: intent voor ${service.name} mislukt: $e');
      } on MissingPluginException catch (e) {
        debugPrint('JT: intentkanaal ontbreekt: $e');
      }
    }
    try {
      await urilauncher.launchUrl(Uri.parse(service.webUrl), mode: urilauncher.LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('JT: ${service.webUrl} openen mislukt: $e');
    }
  }

  /// Vlecht de diensten tussen de bibliotheken, na [insertAfterLibrary].
  /// Zonder bibliotheken (nog niet geladen) komen er ook geen diensten.
  static List<T> weave<T>(
    List<ViewModel> views,
    T Function(ViewModel view) fromView,
    T Function(JtStreamingService service) fromService,
  ) {
    if (views.isEmpty) return const [];
    final anchor = views.indexWhere(
      (view) => view.name.trim().toLowerCase() == insertAfterLibrary.toLowerCase(),
    );
    final at = anchor == -1 ? views.length : anchor + 1;
    return [
      ...views.take(at).map(fromView),
      ...all.map(fromService),
      ...views.skip(at).map(fromView),
    ];
  }

  /// Logo in dezelfde maat en vorm als een bibliotheekicoon (ViewModel.createIcon).
  static Widget icon(JtStreamingService service, {double dimension = 45}) {
    return ClipRRect(
      borderRadius: FladderTheme.smallShape.borderRadius,
      child: SizedBox.square(
        dimension: dimension,
        child: Image.asset(
          service.logoAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
