/// Windows/Android: there is no service worker, the update check does nothing.
Future<String?> jtFetchNoStore(String url) async => null;

int? jtUpdateIntervalOverride() => null;

Future<void> jtHardReload() async {}

void jtUpdateLog(String message) {}
