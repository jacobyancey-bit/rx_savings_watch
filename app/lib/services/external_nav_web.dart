import 'dart:js_interop';

@JS('window.location.assign')
external void _locationAssign(String url);

@JS('window.open')
external JSAny? _windowOpen(String url, String target, String features);

/// Web implementation using real browser navigation so same-origin server-rendered
/// routes like `/partners` bypass Flutter's internal Navigator cleanly.
class ExternalNavService {
  static Future<bool> openUrl(String url, {bool sameTab = false}) async {
    try {
      if (sameTab) {
        _locationAssign(url);
        return true;
      }
      final opened = _windowOpen(url, '_blank', 'noopener,noreferrer');
      if (opened == null) {
        _locationAssign(url);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
