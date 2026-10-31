import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// POST [url] with `keepalive`, so the browser finishes it after the tab closes.
bool jtPostKeepalive(String url, Map<String, String> headers, String? body) {
  try {
    final init = JSObject()
      ..['method'] = 'POST'.toJS
      ..['keepalive'] = true.toJS
      ..['headers'] = headers.jsify();
    if (body != null) init['body'] = body.toJS;
    globalContext.callMethod<JSAny?>('fetch'.toJS, url.toJS, init);
    return true;
  } catch (_) {
    return false;
  }
}

/// Flutter web only reports `detached` once no views are left, so it never sees a
/// closed tab or a reload. `pagehide` is the last event that reliably fires then.
void jtOnPageHide(void Function() callback) {
  globalContext.callMethod<JSAny?>('addEventListener'.toJS, 'pagehide'.toJS, ((JSAny _) => callback()).toJS);
}
