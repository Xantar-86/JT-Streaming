import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jt/jt_streaming_services.dart';
import 'package:fladder/models/view_model.dart';

ViewModel _view(String name) => ViewModel.createEmpty(name, CollectionType.folders).copyWith(name: name);

List<String> _names(List<ViewModel> views) => JtStreamingServices.weave<String>(
      views,
      (view) => view.name,
      (service) => service.name,
    );

void main() {
  test('diensten komen direct na Apple TV+ Series', () {
    final views = ['Mappen', 'Live-tv', 'Apple TV+ Series', 'Collecties'].map(_view).toList();
    expect(_names(views), ['Mappen', 'Live-tv', 'Apple TV+ Series', 'vtm GO', 'GOPlay', 'Collecties']);
  });

  test('zonder Apple TV+ Series komen ze achteraan', () {
    final views = ['Mappen', 'Collecties'].map(_view).toList();
    expect(_names(views), ['Mappen', 'Collecties', 'vtm GO', 'GOPlay']);
  });

  test('zonder bibliotheken geen diensten', () {
    expect(_names(const []), isEmpty);
  });

  test('elke dienst heeft een logo, een intent en een website', () {
    for (final service in JtStreamingServices.all) {
      expect(service.logoAsset, startsWith('assets/jt/'));
      expect(service.androidIntentUri, startsWith('intent://'));
      expect(service.androidIntentUri, contains('package='));
      expect(Uri.parse(service.webUrl).scheme, 'https');
    }
  });
}
