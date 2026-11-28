import 'dart:js_interop';

@JS('window.location.assign')
external void _locationAssign(String url);

@JS('window.open')
external _JsWindow? _windowOpen(String url, String target);

extension type _JsWindow._(JSObject _) implements JSObject {
  external set opener(JSAny? value);
}

/// Web implementation using real browser navigation so same-origin server-rendered
/// routes like `/partners` bypass Flutter's internal Navigator cleanly.
class ExternalNavService {
  static Future<bool> openUrl(String url, {bool sameTab = false}) async {
    try {
      if (sameTab) {
        _locationAssign(url);
        return true;
      }
      // NOTE: Do not pass the 'noopener' window feature here. Per the HTML spec,
      // window.open(..., 'noopener') ALWAYS returns null, which made the old
      // "popup blocked" fallback navigate the app tab away on every click.
      // Instead, open normally and sever the opener reference manually. Referrer
      // leakage is already prevented by the page-wide `Referrer-Policy: no-referrer`.
      final opened = _windowOpen(url, '_blank');
      if (opened == null) {
        // Genuinely blocked by a popup blocker: fall back to same-tab navigation.
        _locationAssign(url);
        return true;
      }
      try {
        opened.opener = null;
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }
}
