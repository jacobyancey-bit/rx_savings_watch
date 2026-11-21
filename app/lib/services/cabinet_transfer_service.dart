import 'api_service.dart';

/// Zero-server, zero-PII cabinet transfer encoder & decoder.
///
/// Privacy guarantee:
/// - Transfer links place RxCUI codes ONLY inside the URL hash fragment (`#import=...`).
/// - Per RFC 3986, browsers NEVER transmit the `#` fragment to any web server,
///   proxy, or server access log.
/// - No patient name, account ID, dosage, or personal info is ever included.
class CabinetTransferService {
  static const int maxImportCount = 50;
  static final RegExp _rxcuiRegex = RegExp(r'^\d{1,12}$');

  /// Builds a zero-server transfer link like:
  /// `https://rx.dangling-dice-studios.com/#import=12345,67890`
  static String buildTransferLink(List<String> rxcuis, {String? baseUrl}) {
    final clean = _sanitizeRxcuis(rxcuis);
    final base = (baseUrl ?? ApiService.productionBaseUrl).replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return base;
    return '$base/#import=${clean.join(',')}';
  }

  /// Builds a compact copy/paste transfer code like `RXW:12345,67890`.
  static String buildTransferCode(List<String> rxcuis) {
    final clean = _sanitizeRxcuis(rxcuis);
    if (clean.isEmpty) return '';
    return 'RXW:${clean.join(',')}';
  }

  /// Extracts validated numeric RxCUIs from a URL, `#import=...` fragment,
  /// `RXW:...` short code, or comma/whitespace-separated list.
  static List<String> parseRxcuisFromInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    String payload = trimmed;

    // 1. If a full URL or fragment containing `import=` was pasted
    final importMatch = RegExp(r'import=([0-9,\s]+)', caseSensitive: false).firstMatch(trimmed);
    if (importMatch != null) {
      payload = importMatch.group(1) ?? '';
    } else {
      // 2. If a short code like `RXW:12345,67890` was pasted
      final codeMatch = RegExp(r'RXW:([0-9,\s]+)', caseSensitive: false).firstMatch(trimmed);
      if (codeMatch != null) {
        payload = codeMatch.group(1) ?? '';
      }
    }

    final parts = payload.split(RegExp(r'[\s,;]+'));
    return _sanitizeRxcuis(parts);
  }

  static List<String> _sanitizeRxcuis(Iterable<String> rawItems) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in rawItems) {
      final s = item.trim();
      if (_rxcuiRegex.hasMatch(s) && seen.add(s)) {
        result.add(s);
        if (result.length >= maxImportCount) break;
      }
    }
    return result;
  }
}
