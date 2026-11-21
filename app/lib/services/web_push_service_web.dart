import 'dart:convert';
import 'dart:js_interop';

@JS('rxPush')
external _RxPushBridge? get _rxPush;

extension type _RxPushBridge(JSObject _) implements JSObject {
  external bool isSupported();
  external JSPromise<JSString> getStatus();
  external JSPromise<JSBoolean> syncWatchedRxcuis(String rxcuisJson);
  external JSPromise<JSString> subscribe(String apiBaseUrl);
  external JSPromise<JSString> unsubscribe(String apiBaseUrl);
  external JSPromise<JSBoolean> showLocalTestNotification();
}

/// Web implementation calling window.rxPush (Service Worker + IndexedDB local filtering).
class WebPushService {
  static bool isSupported() {
    try {
      return _rxPush?.isSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> getStatus() async {
    try {
      final bridge = _rxPush;
      if (bridge == null) return 'unsupported';
      final result = await bridge.getStatus().toDart;
      return result.toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<void> syncWatchedRxcuis(List<String> rxcuis) async {
    try {
      final bridge = _rxPush;
      if (bridge == null) return;
      await bridge.syncWatchedRxcuis(jsonEncode(rxcuis)).toDart;
    } catch (_) {}
  }

  static Future<String> subscribe(String apiBaseUrl) async {
    try {
      final bridge = _rxPush;
      if (bridge == null) return 'unsupported';
      final result = await bridge.subscribe(apiBaseUrl).toDart;
      return result.toDart;
    } catch (_) {
      return 'error';
    }
  }

  static Future<String> unsubscribe(String apiBaseUrl) async {
    try {
      final bridge = _rxPush;
      if (bridge == null) return 'unsupported';
      final result = await bridge.unsubscribe(apiBaseUrl).toDart;
      return result.toDart;
    } catch (_) {
      return 'error';
    }
  }

  static Future<bool> showLocalTestNotification() async {
    try {
      final bridge = _rxPush;
      if (bridge == null) return false;
      final result = await bridge.showLocalTestNotification().toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }
}
