import 'package:url_launcher/url_launcher.dart';

/// Native mobile/desktop implementation for navigating to external or server-rendered URLs.
class ExternalNavService {
  static Future<bool> openUrl(String url, {bool sameTab = false}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
