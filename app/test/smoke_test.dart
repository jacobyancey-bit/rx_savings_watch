import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rx_savings_watch/models/drug.dart';
import 'package:rx_savings_watch/models/medication_reminder.dart';
import 'package:rx_savings_watch/models/patient_cabinet.dart';
import 'package:rx_savings_watch/providers/cabinet_provider.dart';
import 'package:rx_savings_watch/screens/home_screen.dart';
import 'package:rx_savings_watch/services/api_service.dart';
import 'package:rx_savings_watch/services/notification_service.dart';
import 'package:rx_savings_watch/services/storage_service.dart';

class _SmokeStorageService extends StorageService {
  List<PatientCabinet> cabinets = [];
  String activeId = PatientCabinet.defaultId;

  @override
  Future<List<PatientCabinet>> loadCabinets() async =>
      cabinets.isEmpty ? [PatientCabinet.emptyDefault()] : List.from(cabinets);

  @override
  Future<void> saveCabinets(List<PatientCabinet> next) async {
    cabinets = List.from(next);
  }

  @override
  Future<String> getActiveCabinetId() async => activeId;

  @override
  Future<void> saveActiveCabinetId(String id) async {
    activeId = id;
  }

  @override
  Future<String?> getCustomServerUrl() async => null;

  @override
  Future<String?> getLastCheckedTimestamp() async => '2026-11-22T12:00:00Z';

  @override
  Future<void> saveLastCheckedTimestamp(String timestamp) async {}

  @override
  Future<bool> getAllowLaunchNotifications() async => true;

  @override
  Future<bool> getAllowShortageNotifications() async => true;

  @override
  Future<double> getTextScale() async => 1.0;

  @override
  Future<void> clearAllLocalData() async {
    cabinets = [];
    activeId = PatientCabinet.defaultId;
  }
}

class _SmokeApiService extends ApiService {
  final List<List<String>> recordedRxcuiPayloads = [];

  @override
  Future<Map<String, dynamic>> checkUpdates({
    required List<String> rxcuis,
    String? lastChecked,
    bool enableChaffing = true,
  }) async {
    recordedRxcuiPayloads.add(List<String>.from(rxcuis));
    return {
      'success': true,
      'checked_at': '2026-11-22T12:00:00Z',
      'updates_found': 0,
      'drugs': const [],
    };
  }
}

class _SmokeNotificationService extends NotificationService {
  final List<String> scheduled = [];
  final List<String> cancelled = [];

  @override
  Future<void> scheduleDailyMedicationReminder(
    MedicationReminder reminder, {
    String cabinetId = 'default',
  }) async {
    scheduled.add('$cabinetId::${reminder.rxcui}::${reminder.notificationTitle}');
  }

  @override
  Future<void> cancelMedicationReminders(
    String rxcui, {
    String cabinetId = 'default',
  }) async {
    cancelled.add('$cabinetId::$rxcui');
  }
}

void main() {
  testWidgets(
    'End-to-End UI Smoke Test: Daily Reminders, Taken Today, and Caregiver Multi-Cabinet',
    (tester) async {
      // Use a realistic phone viewport
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _SmokeStorageService();
      final api = _SmokeApiService();
      final notifs = _SmokeNotificationService();

      storage.cabinets = [
        PatientCabinet.emptyDefault(
          drugs: [
            Drug(
              rxcui: '855333',
              brandName: 'Vyvanse',
              genericName: 'lisdexamfetamine dimesylate',
              hasApprovedGeneric: true,
              commercialGenericAvailable: true,
            ),
          ],
        ),
      ];

      final provider = CabinetProvider(
        storageService: storage,
        apiService: api,
        notificationService: notifs,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<CabinetProvider>.value(
          value: provider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Default cabinet renders cleanly with zero caregiver clutter
      expect(find.text('My Medication Cabinet (1)'), findsOneWidget);
      expect(find.text('Vyvanse'), findsOneWidget);
      expect(find.text('Set Daily Reminder'), findsOneWidget);

      // 2. Open ReminderSheet from DrugCard and save default Morning (8:00 AM) reminder
      await tester.tap(find.text('Set Daily Reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Daily Reminder'), findsOneWidget);
      expect(find.textContaining('Morning'), findsOneWidget);
      expect(find.text('Hide drug name on lock screen'), findsOneWidget);

      await tester.tap(find.text('Save Reminder'));
      await tester.pumpAndSettle();

      expect(find.text('8:00 AM'), findsOneWidget);
      expect(find.text('Mark Taken'), findsOneWidget);
      expect(notifs.scheduled.last, 'default::855333::Time for Vyvanse');

      // 3. Toggle Taken Today directly on the card
      await tester.tap(find.text('Mark Taken'));
      await tester.pumpAndSettle();
      expect(find.text('Taken Today'), findsOneWidget);

      // 4. Open Caregiver Cabinet Switcher by tapping the header
      await tester.tap(find.text('My Medication Cabinet (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Medication Cabinets'), findsOneWidget);

      // 5. Create a new caregiver cabinet ("Mom")
      await tester.tap(find.text('Add Patient / Family Cabinet'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mom');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Verify clean isolation: Mom's cabinet is active and empty
      expect(find.text("Mom's Cabinet (0)"), findsOneWidget);
      expect(find.text('Vyvanse'), findsNothing);

      // 6. Add Eliquis to Mom's cabinet and set a reminder -> verify labeled notification
      await provider.addDrug(
        Drug(
          rxcui: '1364430',
          brandName: 'Eliquis',
          genericName: 'apixaban',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Mom's Cabinet (1)"), findsOneWidget);
      expect(find.text('Eliquis'), findsOneWidget);

      await tester.tap(find.text('Set Daily Reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Reminder'));
      await tester.pumpAndSettle();

      final momId = provider.activeCabinetId;
      expect(notifs.scheduled.last, "$momId::1364430::Time for Mom's Eliquis");

      // 7. Verify zero PII ever sent to API (only numeric RxCUIs)
      for (final payload in api.recordedRxcuiPayloads) {
        for (final id in payload) {
          expect(RegExp(r'^\d+$').hasMatch(id), true, reason: 'Only numeric RxCUIs may leave device');
        }
      }

      // 8. Switch back to My Cabinet and verify original state is untouched
      await tester.tap(find.text("Mom's Cabinet (1)"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Cabinet'));
      await tester.pumpAndSettle();

      expect(find.text('My Medication Cabinet (1)'), findsOneWidget);
      expect(find.text('Vyvanse'), findsOneWidget);
      expect(find.text('Taken Today'), findsOneWidget);
    },
  );
}
