import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/alert_event.dart';
import 'package:rx_savings_watch/models/drug.dart';
import 'package:rx_savings_watch/models/pricing_info.dart';

void main() {
  group('Models Unit Tests', () {
    test('PricingInfo parses and calculates savings', () {
      final json = {
        'brand_nadac_unit_price': 12.85,
        'generic_nadac_unit_price': 0.88,
        'estimated_savings_pct': 93.15,
      };

      final pricing = PricingInfo.fromJson(json);
      expect(pricing.brandNadacUnitPrice, 12.85);
      expect(pricing.genericNadacUnitPrice, 0.88);
      expect(pricing.estimatedSavingsPct, 93.15);
    });

    test('AlertEvent parses details and confidence score', () {
      final json = {
        'id': 1,
        'event_type': 'commercial_generic_launch',
        'signal_summary': 'Commercial generic launch detected',
        'details': {'lag_days': 5},
        'confidence_score': 1.0,
        'detected_at': '2023-08-30',
      };

      final alert = AlertEvent.fromJson(json);
      expect(alert.eventType, 'commercial_generic_launch');
      expect(alert.confidenceScore, 1.0);
      expect(alert.details['lag_days'], 5);
    });

    test('Drug copyWithUpdate merges server sync update correctly', () {
      final drug = Drug(
        rxcui: '855333',
        brandName: 'Vyvanse',
        genericName: 'lisdexamfetamine dimesylate',
        hasApprovedGeneric: false,
        commercialGenericAvailable: false,
      );

      final updateJson = {
        'rxcui': '855333',
        'has_approved_generic': true,
        'commercial_generic_available': true,
        'generic_manufacturers_count': 3,
        'pricing': {
          'brand_nadac_unit_price': 12.85,
          'generic_nadac_unit_price': 0.88,
          'estimated_savings_pct': 93.2,
        },
        'has_active_shortage': true,
        'active_shortage_details': [
          {'status': 'Current', 'reason': 'Manufacturing delay'}
        ],
      };

      final updatedDrug = drug.copyWithUpdate(updateJson);
      expect(updatedDrug.hasApprovedGeneric, true);
      expect(updatedDrug.commercialGenericAvailable, true);
      expect(updatedDrug.genericManufacturersCount, 3);
      expect(updatedDrug.pricing?.estimatedSavingsPct, 93.2);
      expect(updatedDrug.hasActiveShortage, true);
    });
  });
}
