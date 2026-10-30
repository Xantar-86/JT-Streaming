import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// POST [url] with `keepalive`, so the browser finishes it after the tab closes.
void jtPostKeepalive(String url, Map<String, String> headers) {
  final init = JSObject()
    ..['method'] = 'POST'.toJS
    ..['keepalive'] = true.toJS
    ..['headers'] = headers.jsify();
  globalContext.callMethod<JSAny?>('fetch'.toJS, url.toJS, init);
}
