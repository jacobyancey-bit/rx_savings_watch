import '../models/drug.dart';

class BottleScanParseResult {
  final Drug? matchedCatalogDrug;
  final String? queryTerm;
  final String? detectedNdc;

  const BottleScanParseResult({
    this.matchedCatalogDrug,
    this.queryTerm,
    this.detectedNdc,
  });

  bool get hasResult => matchedCatalogDrug != null || (queryTerm != null && queryTerm!.isNotEmpty);
}

/// Pure on-device pharmacy bottle label parser.
/// Extracts ONLY a medication name or NDC number while discarding all
/// personal information (patient name, Rx #, doctor name, pharmacy address, dates).
class BottleLabelParser {
  static final RegExp _ndcPattern = RegExp(r'\b\d{4,5}-\d{3,4}(?:-\d{1,2})?\b');
  static final RegExp _dosageLinePattern = RegExp(
    r'\b([A-Za-z][A-Za-z\-]{2,28}(?:\s+[A-Za-z][A-Za-z\-]{2,20})?)\s+\d+(?:\.\d+)?\s*(?:MG|MCG|ML|GM|G|%|UNIT|UNITS|TAB|TABS|CAP|CAPS)\b',
    caseSensitive: false,
  );

  static const Set<String> _ignoredWords = {
    'TAKE', 'ONE', 'TWO', 'THREE', 'TABLET', 'TABLETS', 'CAPSULE', 'CAPSULES',
    'DAILY', 'TWICE', 'EVERY', 'HOUR', 'HOURS', 'DAYS', 'DAY', 'WEEK', 'MONTH',
    'MOUTH', 'ORAL', 'BY', 'WITH', 'FOOD', 'WATER', 'BEDTIME', 'MORNING',
    'REFILL', 'REFILLS', 'NO', 'QTY', 'QUANTITY', 'DISP', 'DATE', 'FILLED',
    'PRESCRIBER', 'DOCTOR', 'DR', 'MD', 'DO', 'NP', 'PA', 'PHARMACY', 'RX',
    'CVS', 'WALGREENS', 'WALMART', 'RITE', 'AID', 'COSTCO', 'KROGER', 'PUBLIX',
    'TARGET', 'MEIJER', 'HEB', 'SAFEWAY', 'PATIENT', 'NAME', 'ADDRESS', 'PHONE',
    'CAUTION', 'FEDERAL', 'LAW', 'PROHIBITS', 'TRANSFER', 'DISCARD', 'AFTER',
    'EXP', 'EXPIRES', 'LOT', 'MFG', 'NDC', 'STORE', 'ROOM', 'TEMP', 'KEEP',
    'OUT', 'REACH', 'CHILDREN', 'GENERIC', 'FOR', 'SUBSTITUTED', 'COMMON',
    'BRAND', 'BEFORE', 'NEEDED', 'PAIN', 'USE', 'ONLY', 'AS', 'DIRECTED',
  };

  /// Extract only the medication match or search term from raw OCR text.
  /// Raw OCR text is never returned or stored.
  static BottleScanParseResult parse(String rawOcrText, List<Drug> knownCatalog) {
    if (rawOcrText.trim().isEmpty) {
      return const BottleScanParseResult();
    }

    final normalizedUpper = rawOcrText.toUpperCase();

    // 1. Highest-precision match: check against known canonical catalog drugs first
    for (final drug in knownCatalog) {
      final brand = drug.brandName?.trim().toUpperCase();
      if (brand != null && brand.length >= 4) {
        final brandWord = brand.split(' ').first;
        if (brandWord.length >= 4 && RegExp('\\b${RegExp.escape(brandWord)}\\b').hasMatch(normalizedUpper)) {
          return BottleScanParseResult(
            matchedCatalogDrug: drug,
            queryTerm: drug.displayName,
          );
        }
      }
      final genericFirst = drug.genericName.trim().toUpperCase().split(' ').first;
      if (genericFirst.length >= 5 && RegExp('\\b${RegExp.escape(genericFirst)}\\b').hasMatch(normalizedUpper)) {
        return BottleScanParseResult(
          matchedCatalogDrug: drug,
          queryTerm: drug.displayName,
        );
      }
    }

    // 2. Look for a line containing "<DRUG NAME> <STRENGTH> MG/MCG/ML"
    // Standard U.S. pharmacy labels print the drug name immediately before the strength.
    final lines = rawOcrText.split(RegExp(r'[\r\n]+'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final upperLine = line.toUpperCase();

      // Skip obvious PII/address/instruction lines
      if (upperLine.contains('RX#') ||
          upperLine.contains('RX ') ||
          upperLine.contains('DR.') ||
          upperLine.contains('DR ') ||
          upperLine.contains('DOB') ||
          upperLine.contains('PHONE') ||
          upperLine.contains('PHARMACY') ||
          upperLine.contains('TAKE ') ||
          upperLine.contains('REFILL')) {
        continue;
      }

      final match = _dosageLinePattern.firstMatch(line);
      if (match != null) {
        final candidate = match.group(1)!.trim();
        final words = candidate
            .split(RegExp(r'\s+'))
            .where((w) => w.length >= 3 && !_ignoredWords.contains(w.toUpperCase()))
            .toList();
        if (words.isNotEmpty) {
          return BottleScanParseResult(queryTerm: words.join(' '));
        }
      }
    }

    // 3. Fallback: extract NDC code if printed on the bottle
    final ndcMatch = _ndcPattern.firstMatch(rawOcrText);
    if (ndcMatch != null) {
      return BottleScanParseResult(
        detectedNdc: ndcMatch.group(0),
        queryTerm: ndcMatch.group(0),
      );
    }

    return const BottleScanParseResult();
  }
}
