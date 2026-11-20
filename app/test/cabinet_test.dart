import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/drug.dart';
import 'package:rx_savings_watch/providers/cabinet_provider.dart';
import 'package:rx_savings_watch/services/api_service.dart';
import 'package:rx_savings_watch/services/storage_service.dart';

class MockStorageService extends StorageService {
  List<Drug> storedCabinet = [];
  String? storedLastChecked;
  String? storedUrl;

  @override
  Future<List<Drug>> loadCabinet() async => List.from(storedCabinet);

  @override
  Future<void> saveCabinet(List<Drug> drugs) async {
    storedCabinet = List.from(drugs);
  }

  @override
  Future<String?> getLastCheckedTimestamp() async => storedLastChecked;

  @override
  Future<void> saveLastCheckedTimestamp(String timestamp) async {
    storedLastChecked = timestamp;
  }

  @override
  Future<String?> getCustomServerUrl() async => storedUrl;

  @override
  Future<void> saveCustomServerUrl(String url) async {
    storedUrl = url;
  }
}

class MockApiService extends ApiService {
  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<Map<String, dynamic>> checkUpdates({
    required List<String> rxcuis,
    String? lastChecked,
  }) async {
    return {
      'success': true,
      'checked_at': '2026-11-20T20:00:00Z',
      'updates_found': 1,
      'drugs': [
        {
          'rxcui': '855333',
          'brand_name': 'Vyvanse',
          'generic_name': 'lisdexamfetamine dimesylate',
          'has_approved_generic': true,
          'commercial_generic_available': true,
          'pricing': {
            'brand_nadac_unit_price': 12.85,
            'generic_nadac_unit_price': 0.88,
            'estimated_savings_pct': 93.2,
          },
          'has_active_shortage': false,
          'alerts': [],
        }
      ],
    };
  }
}

void main() {
  group('CabinetProvider Tests', () {
    test('Adds and removes drugs with state notifications', () async {
      final mockStorage = MockStorageService();
      final mockApi = MockApiService();
      final provider = CabinetProvider(storageService: mockStorage, apiService: mockApi);

      // Wait for provider _init
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.cabinet.isEmpty, true);

      final vyvanse = Drug(
        rxcui: '855333',
        brandName: 'Vyvanse',
        genericName: 'lisdexamfetamine dimesylate',
      );

      await provider.addDrug(vyvanse);

      expect(provider.cabinet.length, 1);
      expect(provider.isWatched('855333'), true);
      expect(mockStorage.storedCabinet.length, 1);

      // Verify sync updated the drug
      final updatedVyvanse = provider.cabinet.first;
      expect(updatedVyvanse.commercialGenericAvailable, true);
      expect(updatedVyvanse.pricing?.estimatedSavingsPct, 93.2);

      // Verify summary calculations
      expect(provider.genericLaunchedCount, 1);
      expect(provider.maxSavingsAvailable, 93.2);

      // Remove drug
      await provider.removeDrug('855333');
      expect(provider.cabinet.isEmpty, true);
      expect(mockStorage.storedCabinet.isEmpty, true);
    });
  });
}
