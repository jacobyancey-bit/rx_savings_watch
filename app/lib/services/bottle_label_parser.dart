import '../models/drug.dart';

class BottleScanParseResult {
  final Drug? matchedCatalogDrug;
  final String? queryTerm;
  final String? detectedNdc;
  final String? detectedStrength;
  final List<String> ambiguousCandidates;

  const BottleScanParseResult({
    this.matchedCatalogDrug,
    this.queryTerm,
    this.detectedNdc,
    this.detectedStrength,
    this.ambiguousCandidates = const [],
  });

  bool get hasResult =>
      matchedCatalogDrug != null ||
      (queryTerm != null && queryTerm!.isNotEmpty) ||
      ambiguousCandidates.isNotEmpty;
}

/// Pure on-device pharmacy bottle label parser.
/// Extracts ONLY a medication name or NDC number while discarding all
/// personal information (patient name, Rx #, doctor name, pharmacy address, dates).
class BottleLabelParser {
  static final RegExp _ndcPattern = RegExp(r'\b\d{4,5}-\d{3,4}(?:-\d{1,2})?\b');
  static final RegExp _dosageLinePattern = RegExp(
    r'\b([A-Za-z][A-Za-z\-\/\.]{2,28}(?:\s+[A-Za-z][A-Za-z\-\/\.]{1,20})?)\s+\d+(?:\.\d+)?\s*(?:MG|M6|MQ|MCG|ML|GM|G|%|UNIT|UNITS|TAB|TABS|CAP|CAPS)\b',
    caseSensitive: false,
  );
  static final RegExp _cleanWordPattern = RegExp(r'^[A-Za-z][A-Za-z\-\/]{3,26}$');

  /// Common shortened U.S. pharmacy bottle label abbreviations mapped to
  /// canonical FDA/RxNorm search terms (longest/most specific keys checked first).
  static const Map<String, String> _pharmacyAbbreviations = {
    'AMPHET/DEXTR': 'Adderall',
    'AMPHET-DEXTR': 'Adderall',
    'AMPHET DEXTR': 'Adderall',
    'D-AMPHET': 'Adderall',
    'AMPHETAMINE SALTS': 'Adderall',
    'AMPHET': 'Adderall',
    'DEXTR': 'Adderall',
    'AMOX/CLAV': 'amoxicillin-clavulanate',
    'AMOX-CLAV': 'amoxicillin-clavulanate',
    'SULFAMETH/TMP': 'sulfamethoxazole-trimethoprim',
    'SMZ-TMP': 'sulfamethoxazole-trimethoprim',
    'SMZ/TMP': 'sulfamethoxazole-trimethoprim',
    'FLUTIC/SALM': 'fluticasone-salmeterol',
    'BUDES/FORMOT': 'Symbicort',
    'EMTRIC/TENOF': 'Truvada',
    'HYDROCOD/APAP': 'hydrocodone-acetaminophen',
    'OXYCOD/APAP': 'oxycodone-acetaminophen',
    'LOSARTAN/HCTZ': 'losartan-hydrochlorothiazide',
    'LISINOP/HCTZ': 'lisinopril-hydrochlorothiazide',
    'METHYLPHENID': 'methylphenidate',
    'METHYLPHEN': 'methylphenidate',
    'LISDEXAMFET': 'Vyvanse',
    'LISDEX': 'Vyvanse',
    'HYDROCHLOROT': 'hydrochlorothiazide',
    'HCTZ': 'hydrochlorothiazide',
    'ATORVAST': 'atorvastatin',
    'LEVOTHYROX': 'levothyroxine',
    'METOPROL': 'metoprolol',
    'ROSUVAST': 'rosuvastatin',
    'ESCITALOP': 'escitalopram',
    'SERTRAL': 'sertraline',
    'GABAPENT': 'gabapentin',
    'OMEPRAZ': 'omeprazole',
    'PANTOPRAZ': 'pantoprazole',
    'MONTELUK': 'montelukast',
    'ALBUTER': 'albuterol',
    'SEMAGLUT': 'Ozempic',
    'TIRZEPAT': 'tirzepatide',
    'APIXAB': 'Eliquis',
    'RIVAROX': 'rivaroxaban',
    'EMPAGLIF': 'Jardiance',
    'LISINOP': 'lisinopril',
    'AMLODIP': 'amlodipine',
    'METFORM': 'metformin',
    'WARFAR': 'warfarin',
  };

  static final RegExp _genericForPattern = RegExp(
    r'(?:GENERIC\s+FOR|GEN\s+FOR|SUBSTITUTED\s+FOR|COMMON\s+BRAND(?:\(S\))?:?)\s+([A-Za-z][A-Za-z0-9\-]{2,24}(?:\s+(?:XR|ER|PM|LA|SR|DR|CR|CD|HFA))?)',
    caseSensitive: false,
  );

  static bool _isAmphetSaltLabel(String normalizedUpper) {
    return normalizedUpper.contains('AMPHET/DEXTR') ||
        normalizedUpper.contains('AMPHET-DEXTR') ||
        normalizedUpper.contains('AMPHET DEXTR') ||
        normalizedUpper.contains('D-AMPHET') ||
        normalizedUpper.contains('AMPHETAMINE SALTS') ||
        normalizedUpper.contains('AMPHET') ||
        normalizedUpper.contains('DEXTR');
  }

  static BottleScanParseResult? _resolveAmphetSaltDisambiguation(
    String normalizedUpper,
    String? detectedStrength,
    List<Drug> knownCatalog,
  ) {
    if (!_isAmphetSaltLabel(normalizedUpper)) return null;

    Drug? findInCatalog(String brandName) {
      final upper = brandName.toUpperCase();
      for (final d in knownCatalog) {
        if ((d.brandName ?? '').trim().toUpperCase() == upper) return d;
      }
      return null;
    }

    // 1. Unique Mydayis strengths (Adderall XR does NOT exist in 12.5, 37.5, or 50 mg)
    final strengthNum = detectedStrength != null
        ? RegExp(r'\d+(?:\.\d+)?').firstMatch(detectedStrength)?.group(0)
        : null;

    if (strengthNum == '12.5' || strengthNum == '37.5' || strengthNum == '50') {
      final catalogHit = findInCatalog('Mydayis');
      return BottleScanParseResult(
        matchedCatalogDrug: catalogHit,
        queryTerm: catalogHit?.displayName ?? 'Mydayis',
        detectedStrength: detectedStrength,
      );
    }

    // 2. Unique Adderall XR strengths (Mydayis does NOT exist in 5, 10, 15, 20, or 30 mg)
    if (strengthNum == '5' ||
        strengthNum == '10' ||
        strengthNum == '15' ||
        strengthNum == '20' ||
        strengthNum == '30') {
      final targetBrand = RegExp(r'\b(XR|ER|EXT|EXTENDED|CAP|CAPS)\b').hasMatch(normalizedUpper)
          ? 'Adderall XR'
          : 'Adderall XR';
      final catalogHit = findInCatalog(targetBrand);
      return BottleScanParseResult(
        matchedCatalogDrug: catalogHit,
        queryTerm: catalogHit?.displayName ?? targetBrand,
        detectedStrength: detectedStrength,
      );
    }

    // 3. Shared strength (25 mg) or no strength scanned yet -> let user pick in 1 tap!
    return BottleScanParseResult(
      queryTerm: 'Mydayis',
      detectedStrength: detectedStrength,
      ambiguousCandidates: const ['Mydayis', 'Adderall XR'],
    );
  }

  static String? _matchPharmacyAbbreviation(String normalizedUpper) {
    for (final entry in _pharmacyAbbreviations.entries) {
      if (normalizedUpper.contains(entry.key)) {
        // If this is a single-word truncation prefix and the full drug name is already
        // spelled out on the label (e.g., "WARFARIN SODIUM"), let the normal dosage
        // parser preserve the full label wording.
        if (!entry.key.contains('/') &&
            !entry.key.contains('-') &&
            !entry.key.contains(' ') &&
            normalizedUpper.contains(entry.value.toUpperCase())) {
          continue;
        }
        return entry.value;
      }
    }
    return null;
  }

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
    'EXTENDED', 'RELEASE', 'DELAYED', 'CHEWABLE', 'SOLUTION', 'SUSPENSION',
    'CREAM', 'OINTMENT', 'INHALER', 'PATCH', 'DROPS', 'SPRAY', 'STREET',
    'AVENUE', 'ROAD', 'DRIVE', 'LANE', 'SUITE', 'NORTH', 'SOUTH', 'EAST', 'WEST',
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'JUNE', 'JULY', 'AUGUST',
    'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER', 'PRESCRIPTION', 'WARNING',
    'MAY', 'CAUSE', 'DROWSINESS', 'ALCOHOL', 'REFILLABLE', 'THROUGH', 'UNTIL',
  };

  static final RegExp _strengthOnlyPattern = RegExp(
    r'\b(\d+(?:\.\d+)?)\s*(MG|M6|MQ|MCG|ML|GM|G|%|UNIT|UNITS)\b',
    caseSensitive: false,
  );

  /// Extracts and normalizes a dosage strength like `40 mg` or `12.5 mg` from OCR text.
  static String? extractStrength(String rawOcrText) {
    final m = _strengthOnlyPattern.firstMatch(rawOcrText);
    if (m == null) return null;
    final numStr = m.group(1)!;
    var unit = m.group(2)!.toLowerCase();
    if (unit == 'm6' || unit == 'mq') unit = 'mg';
    if (unit == 'gm') unit = 'g';
    if (unit == 'units') unit = 'unit';
    return unit == '%' ? '$numStr%' : '$numStr $unit';
  }

  /// Extract only the medication match, dosage strength, or search term from raw OCR text.
  /// Raw OCR text is never returned or stored.
  static BottleScanParseResult parse(String rawOcrText, List<Drug> knownCatalog) {
    if (rawOcrText.trim().isEmpty) {
      return const BottleScanParseResult();
    }

    final normalizedUpper = rawOcrText.toUpperCase();
    final detectedStrength = extractStrength(rawOcrText);

    // 0A. Highest priority: explicit "GENERIC FOR <BRAND>" / "COMMON BRAND: <BRAND>" line
    final genericForMatch = _genericForPattern.firstMatch(rawOcrText);
    if (genericForMatch != null) {
      final brandText = genericForMatch.group(1)!.trim();
      final brandUpper = brandText.toUpperCase();
      for (final drug in knownCatalog) {
        final b = drug.brandName?.trim().toUpperCase() ?? '';
        if (b.isNotEmpty && (b == brandUpper || b.startsWith(brandUpper) || brandUpper.startsWith(b))) {
          return BottleScanParseResult(
            matchedCatalogDrug: drug,
            queryTerm: drug.displayName,
            detectedStrength: detectedStrength,
          );
        }
      }
      return BottleScanParseResult(
        queryTerm: brandText,
        detectedStrength: detectedStrength,
      );
    }

    // 0B. Explicit catalog brand match BEFORE generic abbreviations (e.g., "MYDAYIS" anywhere on label)
    for (final drug in knownCatalog) {
      final brand = drug.brandName?.trim().toUpperCase();
      if (brand != null && brand.length >= 4) {
        final brandWord = brand.split(' ').first;
        if (brandWord.length >= 4 && RegExp('\\b${RegExp.escape(brandWord)}\\b').hasMatch(normalizedUpper)) {
          return BottleScanParseResult(
            matchedCatalogDrug: drug,
            queryTerm: drug.displayName,
            detectedStrength: detectedStrength,
          );
        }
      }
    }

    // 0C. Smart clinical disambiguation for mixed amphetamine salts (Mydayis vs Adderall XR)
    final amphetDisambig = _resolveAmphetSaltDisambiguation(
      normalizedUpper,
      detectedStrength,
      knownCatalog,
    );
    if (amphetDisambig != null) {
      return amphetDisambig;
    }

    // 0D. Expand other shortened U.S. pharmacy bottle abbreviations (e.g., AMOX/CLAV, ATORVAST)
    final expandedAbbrev = _matchPharmacyAbbreviation(normalizedUpper);
    if (expandedAbbrev != null) {
      final expandedUpper = expandedAbbrev.toUpperCase();
      for (final drug in knownCatalog) {
        final b = drug.brandName?.trim().toUpperCase() ?? '';
        final g = drug.genericName.trim().toUpperCase();
        if (b == expandedUpper || g == expandedUpper || g.contains(expandedUpper) || b.contains(expandedUpper)) {
          return BottleScanParseResult(
            matchedCatalogDrug: drug,
            queryTerm: drug.displayName,
            detectedStrength: detectedStrength,
          );
        }
      }
      return BottleScanParseResult(
        queryTerm: expandedAbbrev,
        detectedStrength: detectedStrength,
      );
    }

    // 1. Check against known canonical catalog generic names
    for (final drug in knownCatalog) {
      final brand = drug.brandName?.trim().toUpperCase();
      if (brand != null && brand.length >= 4) {
        final brandWord = brand.split(' ').first;
        if (brandWord.length >= 4 && RegExp('\\b${RegExp.escape(brandWord)}\\b').hasMatch(normalizedUpper)) {
          return BottleScanParseResult(
            matchedCatalogDrug: drug,
            queryTerm: drug.displayName,
            detectedStrength: detectedStrength,
          );
        }
      }
      final genericFirst = drug.genericName.trim().toUpperCase().split(' ').first;
      if (genericFirst.length >= 5 && RegExp('\\b${RegExp.escape(genericFirst)}\\b').hasMatch(normalizedUpper)) {
        return BottleScanParseResult(
          matchedCatalogDrug: drug,
          queryTerm: drug.displayName,
          detectedStrength: detectedStrength,
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
          return BottleScanParseResult(
            queryTerm: words.join(' '),
            detectedStrength: extractStrength(line) ?? detectedStrength,
          );
        }
      }
    }

    // 3. Fallback: extract NDC code if printed on the bottle
    final ndcMatch = _ndcPattern.firstMatch(rawOcrText);
    if (ndcMatch != null) {
      return BottleScanParseResult(
        detectedNdc: ndcMatch.group(0),
        queryTerm: ndcMatch.group(0),
        detectedStrength: detectedStrength,
      );
    }

    // 4. Focused viewfinder crop fallback: when the user framed ONLY the medication
    // name inside the teal guide box (1–4 short lines) and the strength was on
    // another line or slightly blurred, extract the cleanest medication candidate.
    final nonEmptyLines = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (nonEmptyLines.length <= 4) {
      for (final line in nonEmptyLines) {
        final upperLine = line.toUpperCase();
        if (upperLine.contains('RX') ||
            upperLine.contains('DR.') ||
            upperLine.contains('DOB') ||
            upperLine.contains('PHONE') ||
            upperLine.contains('PHARMACY') ||
            upperLine.contains('TAKE ') ||
            upperLine.contains('REFILL')) {
          continue;
        }
        final tokens = line
            .replaceAll(RegExp(r'[^A-Za-z\-\s]'), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => _cleanWordPattern.hasMatch(w) && !_ignoredWords.contains(w.toUpperCase()))
            .toList();
        if (tokens.isNotEmpty) {
          final candidate = tokens.take(2).join(' ');
          if (candidate.length >= 5) {
            return BottleScanParseResult(
              queryTerm: candidate,
              detectedStrength: detectedStrength,
            );
          }
        }
      }
    }

    return const BottleScanParseResult();
  }
}
