import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// GET [url] with `cache: no-store` (bypasses the HTTP cache and, because
/// the URL is not in the Flutter RESOURCES list, the service worker).
Future<String?> jtFetchNoStore(String url) async {
  final init = JSObject()..['cache'] = 'no-store'.toJS;
  final response = await globalContext.callMethod<JSPromise<JSObject>>('fetch'.toJS, url.toJS, init).toDart;
  if (!(response['ok'] as JSBoolean).toDart) return null;
  final text = await response.callMethod<JSPromise<JSString>>('text'.toJS).toDart;
  return text.toDart;
}

/// Test hook: `localStorage['jt-update-interval-s']` shortens the 30 min poll.
int? jtUpdateIntervalOverride() {
  try {
    final storage = globalContext['localStorage'] as JSObject?;
    final value = storage?.callMethod<JSAny?>('getItem'.toJS, 'jt-update-interval-s'.toJS);
    return value == null ? null : int.tryParse((value as JSString).toDart);
  } catch (_) {
    return null;
  }
}

void _log(String message) => (globalContext['console'] as JSObject).callMethod<JSAny?>('log'.toJS, message.toJS);

Future<void> _waitActivated(JSObject worker, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final state = (worker['state'] as JSString?)?.toDart;
    if (state == 'activated' || state == 'redundant') return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// "Reload": let the service worker update first (its script is fetched
/// past the HTTP cache, the new worker clears the old caches and reloads the
/// open tabs, see tool/jt/build-web.ps1). Without a new worker: delete the
/// caches, unregister and reload.
Future<void> jtHardReload() async {
  final location = globalContext['location'] as JSObject;
  final navigator = globalContext['navigator'] as JSObject;
  final serviceWorker = navigator['serviceWorker'] as JSObject?;
  try {
    if (serviceWorker != null) {
      final registration =
          await serviceWorker.callMethod<JSPromise<JSAny?>>('getRegistration'.toJS).toDart as JSObject?;
      if (registration != null) {
        await registration.callMethod<JSPromise<JSAny?>>('update'.toJS).toDart;
        final worker = (registration['installing'] ?? registration['waiting']) as JSObject?;
        if (worker != null) {
          _log('[jt-update] new service worker found, waiting for activation');
          await _waitActivated(worker, const Duration(seconds: 15));
          location.callMethod<JSAny?>('reload'.toJS);
          return;
        }
      }
    }
  } catch (e) {
    _log('[jt-update] service worker update failed: $e');
  }
  _log('[jt-update] no new service worker: clearing caches and unregistering');
  try {
    final caches = globalContext['caches'] as JSObject?;
    if (caches != null) {
      final keys = await caches.callMethod<JSPromise<JSArray<JSString>>>('keys'.toJS).toDart;
      for (final key in keys.toDart) {
        await caches.callMethod<JSPromise<JSAny?>>('delete'.toJS, key).toDart;
      }
    }
    if (serviceWorker != null) {
      final registrations =
          await serviceWorker.callMethod<JSPromise<JSArray<JSObject>>>('getRegistrations'.toJS).toDart;
      for (final registration in registrations.toDart) {
        await registration.callMethod<JSPromise<JSAny?>>('unregister'.toJS).toDart;
      }
    }
  } catch (e) {
    _log('[jt-update] cleanup failed: $e');
  }
  location.callMethod<JSAny?>('reload'.toJS);
}

void jtUpdateLog(String message) => _log(message);
