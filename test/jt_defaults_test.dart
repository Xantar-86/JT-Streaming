import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/settings/client_settings_model.dart';

void main() {
  test('new installations show library posters and do not check for Fladder updates', () {
    final settings = ClientSettingsModel.defaultModel();
    expect(settings.usePosterForLibrary, isTrue);
    expect(settings.checkForUpdates, isFalse);
  });
}
