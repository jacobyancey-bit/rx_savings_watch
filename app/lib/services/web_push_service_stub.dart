/// Non-web stub for WebPushService (Android/iOS use local native notifications).
class WebPushService {
  static bool isSupported() => false;
  static Future<String> getStatus() async => 'unsupported';
  static Future<void> syncWatchedRxcuis(List<String> rxcuis) async {}
  static Future<String> subscribe(String apiBaseUrl) async => 'unsupported';
  static Future<String> unsubscribe(String apiBaseUrl) async => 'unsupported';
  static Future<bool> showLocalTestNotification() async => false;
  static bool printHandout(String title, String bodyHtml) => false;
  static void clearUrlHash() {}
}
