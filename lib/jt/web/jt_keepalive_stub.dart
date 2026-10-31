/// Windows/Android: the process outlives its requests, nothing extra is needed.
bool jtPostKeepalive(String url, Map<String, String> headers, String? body) => false;

void jtOnPageHide(void Function() callback) {}
