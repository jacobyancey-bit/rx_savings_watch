import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/drug.dart';
import 'package:rx_savings_watch/services/bottle_label_parser.dart';

void main() {
  group('BottleLabelParser Privacy & Extraction Tests', () {
    final catalog = [
      Drug(
        rxcui: '1364430',
        brandName: 'Eliquis',
        genericName: 'apixaban',
        strength: '5 mg',
        dosageForm: 'oral tablet',
      ),
      Drug(
        rxcui: '855333',
        brandName: 'Vyvanse',
        genericName: 'lisdexamfetamine dimesylate',
        strength: '30 mg',
        dosageForm: 'oral capsule',
      ),
    ];

    test('Extracts known catalog drug and discards all patient PII', () {
      const sampleLabel = '''
        WALGREENS PHARMACY #04122
        123 MAIN ST, DALLAS TX 75201
        PHONE: (555) 234-5678
        RX# 8841293-01   DOB: 04/12/1952
        JANE DOE
        DR. ROBERT SMITH MD
        ELIQUIS 5 MG TABLET
        TAKE ONE TABLET BY MOUTH TWICE DAILY
        QTY: 60   REFILLS: 3
      ''';

      final result = BottleLabelParser.parse(sampleLabel, catalog);
      expect(result.hasResult, isTrue);
      expect(result.matchedCatalogDrug?.rxcui, '1364430');
      expect(result.queryTerm, 'Eliquis');
      expect(result.detectedStrength, '5 mg');
      // Verify zero PII leaked into queryTerm
      expect(result.queryTerm!.contains('JANE'), isFalse);
      expect(result.queryTerm!.contains('8841293'), isFalse);
    });

    test('Extracts unknown medication name from dosage line for live FDA lookup', () {
      const sampleLabel = '''
        CVS PHARMACY
        RX 4491022
        JOHN PUBLIC
        DR. ALICE JONES
        WARFARIN SODIUM 5 MG TABLET
        TAKE 1 TABLET DAILY
      ''';

      final result = BottleLabelParser.parse(sampleLabel, catalog);
      expect(result.hasResult, isTrue);
      expect(result.matchedCatalogDrug, isNull);
      expect(result.queryTerm?.toUpperCase(), 'WARFARIN SODIUM');
    });

    test('Falls back to NDC number when drug name is obscured', () {
      const sampleLabel = '''
        PHARMACY LABEL
        NDC 00378-6170-01
        QTY 30
      ''';

      final result = BottleLabelParser.parse(sampleLabel, catalog);
      expect(result.hasResult, isTrue);
      expect(result.detectedNdc, '00378-6170-01');
      expect(result.queryTerm, '00378-6170-01');
    });

    test('Extracts medication name from focused viewfinder crop without strength', () {
      const focusedCrop = '''
        METOPROLOL SUCCINATE
        EXTENDED RELEASE
      ''';

      final result = BottleLabelParser.parse(focusedCrop, catalog);
      expect(result.hasResult, isTrue);
      expect(result.queryTerm?.toUpperCase(), 'METOPROLOL SUCCINATE');
    });

    test('Expands shortened pharmacy abbreviation like AMPHET/DEXTR with strength', () {
      const abbrevLabel = '''
        AMPHET/DEXTR 20 MG ER CAP
      ''';

      final result = BottleLabelParser.parse(abbrevLabel, catalog);
      expect(result.hasResult, isTrue);
      expect(result.queryTerm, 'Adderall XR');
      expect(result.detectedStrength, '20 mg');
      expect(result.ambiguousCandidates, isEmpty);
    });

    test('Prioritizes GENERIC FOR MYDAYIS 37.5 MG over generic abbreviation', () {
      const mydayisLabel = '''
        AMPHET/DEXTR
        GENERIC FOR MYDAYIS 37.5 MG
      ''';

      final result = BottleLabelParser.parse(mydayisLabel, catalog);
      expect(result.hasResult, isTrue);
      expect(result.queryTerm?.toUpperCase(), 'MYDAYIS');
      expect(result.detectedStrength, '37.5 mg');
    });

    test('Disambiguates AMPHET/DEXTR 37.5 MG automatically to Mydayis by unique strength', () {
      const label = 'AMPHET/DEXTR 37.5 MG CAP';
      final result = BottleLabelParser.parse(label, catalog);
      expect(result.hasResult, isTrue);
      expect(result.queryTerm, 'Mydayis');
      expect(result.detectedStrength, '37.5 mg');
      expect(result.ambiguousCandidates, isEmpty);
    });

    test('Offers Mydayis vs Adderall XR choice for shared 25 mg strength', () {
      const label = 'AMPHET/DEXTR 25 MG CAP';
      final result = BottleLabelParser.parse(label, catalog);
      expect(result.hasResult, isTrue);
      expect(result.detectedStrength, '25 mg');
      expect(result.ambiguousCandidates, containsAll(['Mydayis', 'Adderall XR']));
    });
  });
}
