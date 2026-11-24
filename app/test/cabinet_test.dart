import 'package:flutter_test/flutter_test.dart';
import 'package:rx_savings_watch/models/drug.dart';
import 'package:rx_savings_watch/models/medication_reminder.dart';
import 'package:rx_savings_watch/models/patient_cabinet.dart';
import 'package:rx_savings_watch/providers/cabinet_provider.dart';
import 'package:rx_savings_watch/services/api_service.dart';
import 'package:rx_savings_watch/services/notification_service.dart';
import 'package:rx_savings_watch/services/storage_service.dart';

class MockStorageService extends StorageService {
  List<Drug> storedCabinet = [];
  Map<String, MedicationReminder> storedReminders = {};
  List<PatientCabinet>? storedCabinets;
  String storedActiveCabinetId = PatientCabinet.defaultId;
  String? storedLastChecked;
  String? storedUrl;
  bool allowLaunch = true;
  bool allowShortage = true;
  double storedTextScale = 1.0;
  String? storedLocalZip;

  @override
  Future<String?> getLocalZipCode() async => storedLocalZip;

  @override
  Future<void> saveLocalZipCode(String? zip) async {
    storedLocalZip = zip;
  }

  @override
  Future<List<Drug>> loadCabinet() async => List.from(storedCabinet);

  @override
  Future<void> saveCabinet(List<Drug> drugs) async {
    storedCabinet = List.from(drugs);
  }

  @override
  Future<List<PatientCabinet>> loadCabinets() async {
    if (storedCabinets != null && storedCabinets!.isNotEmpty) {
      return List.from(storedCabinets!);
    }
    return [
      PatientCabinet.emptyDefault(
        drugs: storedCabinet,
        reminders: storedReminders,
      ),
    ];
  }

  @override
  Future<void> saveCabinets(List<PatientCabinet> cabinets) async {
    storedCabinets = List.from(cabinets);
    final def = cabinets.where((c) => c.isDefault).toList();
    if (def.isNotEmpty) {
      storedCabinet = List.from(def.first.drugs);
      storedReminders = Map.from(def.first.reminders);
    }
  }

  @override
  Future<String> getActiveCabinetId() async => storedActiveCabinetId;

  @override
  Future<void> saveActiveCabinetId(String id) async {
    storedActiveCabinetId = id;
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

  @override
  Future<bool> getAllowLaunchNotifications() async => allowLaunch;

  @override
  Future<void> setAllowLaunchNotifications(bool allow) async {
    allowLaunch = allow;
  }

  @override
  Future<bool> getAllowShortageNotifications() async => allowShortage;

  @override
  Future<void> setAllowShortageNotifications(bool allow) async {
    allowShortage = allow;
  }

  @override
  Future<double> getTextScale() async => storedTextScale;

  @override
  Future<void> saveTextScale(double scale) async {
    storedTextScale = scale;
  }

  @override
  Future<Map<String, MedicationReminder>> loadReminders() async => Map.from(storedReminders);

  @override
  Future<void> saveReminders(Map<String, MedicationReminder> reminders) async {
    storedReminders = Map.from(reminders);
  }

  @override
  Future<void> clearAllLocalData() async {
    storedCabinet = [];
    storedReminders = {};
    storedCabinets = null;
    storedActiveCabinetId = PatientCabinet.defaultId;
    storedLastChecked = null;
  }
}

class MockApiService extends ApiService {
  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<Map<String, dynamic>> checkUpdates({
    required List<String> rxcuis,
    String? lastChecked,
    bool enableChaffing = true,
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

class MockNotificationService extends NotificationService {
  bool launchNotified = false;
  bool shortageNotified = false;
  final List<String> scheduledKeys = [];
  final List<String> cancelledKeys = [];

  @override
  Future<void> showGenericLaunchNotification({
    required String drugName,
    String? genericName,
    double? savingsPct,
  }) async {
    launchNotified = true;
  }

  @override
  Future<void> showShortageNotification({
    required String drugName,
    required String reason,
  }) async {
    shortageNotified = true;
  }

  @override
  Future<void> scheduleDailyMedicationReminder(
    MedicationReminder reminder, {
    String cabinetId = 'default',
  }) async {
    scheduledKeys.add('$cabinetId::${reminder.rxcui}::${reminder.notificationTitle}');
  }

  @override
  Future<void> cancelMedicationReminders(
    String rxcui, {
    String cabinetId = 'default',
  }) async {
    cancelledKeys.add('$cabinetId::$rxcui');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CabinetProvider Tests', () {
    test('Adds and removes drugs with state notifications and triggers alert', () async {
      final mockStorage = MockStorageService();
      final mockApi = MockApiService();
      final mockNotifs = MockNotificationService();

      final provider = CabinetProvider(
        storageService: mockStorage,
        apiService: mockApi,
        notificationService: mockNotifs,
      );

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

      // Verify notification was triggered
      expect(mockNotifs.launchNotified, true);

      // Verify summary calculations
      expect(provider.genericLaunchedCount, 1);
      expect(provider.maxSavingsAvailable, 93.2);

      // Remove drug
      await provider.removeDrug('855333');
      expect(provider.cabinet.isEmpty, true);
      expect(mockStorage.storedCabinet.isEmpty, true);
    });

    test('Caregiver multi-cabinet isolates drugs, labels reminders, and cancels alarms on delete', () async {
      final mockStorage = MockStorageService();
      final mockApi = MockApiService();
      final mockNotifs = MockNotificationService();

      final provider = CabinetProvider(
        storageService: mockStorage,
        apiService: mockApi,
        notificationService: mockNotifs,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Create a caregiver cabinet with control characters to verify sanitization
      final mom = await provider.createCabinet(
        name: '  Mom\n\t  ',
        colorValue: PatientCabinet.palette[1],
      );
      expect(mom, isNotNull);
      expect(mom!.name, 'Mom');
      expect(provider.activeCabinetId, mom.id);
      expect(provider.hasMultipleCabinets, true);

      // Add a medication and reminder to Mom's cabinet
      final eliquis = Drug(
        rxcui: '1364430',
        brandName: 'Eliquis',
        genericName: 'apixaban',
      );
      await provider.addDrug(eliquis);
      await provider.saveReminder(
        MedicationReminder(
          rxcui: '1364430',
          drugName: 'Eliquis',
          times: const [ReminderTime(hour: 8, minute: 0)],
        ),
      );

      expect(provider.cabinet.length, 1);
      expect(provider.reminderFor('1364430')?.notificationTitle, "Time for Mom's Eliquis");
      expect(mockNotifs.scheduledKeys.last, "${mom.id}::1364430::Time for Mom's Eliquis");

      // Switch back to default cabinet and verify complete isolation
      await provider.switchCabinet(PatientCabinet.defaultId);
      expect(provider.cabinet.isEmpty, true);
      expect(provider.reminderFor('1364430'), isNull);

      // Delete Mom's cabinet and verify its reminder alarms are cancelled
      final deleted = await provider.deleteCabinet(mom.id);
      expect(deleted, true);
      expect(provider.cabinets.length, 1);
      expect(mockNotifs.cancelledKeys.contains('${mom.id}::1364430'), true);
    });
  });
}
