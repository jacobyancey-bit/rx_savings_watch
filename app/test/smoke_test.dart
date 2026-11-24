import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/link.dart';
import 'package:rx_savings_watch/models/drug.dart';
import 'package:rx_savings_watch/models/medication_reminder.dart';
import 'package:rx_savings_watch/models/patient_cabinet.dart';
import 'package:rx_savings_watch/models/pricing_info.dart';
import 'package:rx_savings_watch/models/refill_info.dart';
import 'package:rx_savings_watch/providers/cabinet_provider.dart';
import 'package:rx_savings_watch/screens/drug_detail_screen.dart';
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

  String? localZip;

  @override
  Future<String?> getLocalZipCode() async => localZip;

  @override
  Future<void> saveLocalZipCode(String? zip) async {
    localZip = zip;
  }

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
  final List<String> refillScheduled = [];
  final List<String> refillCancelled = [];

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

  @override
  Future<void> scheduleRefillReminder(
    RefillInfo refill, {
    String cabinetId = 'default',
  }) async {
    refillScheduled.add('$cabinetId::${refill.rxcui}::${refill.notificationTitle}');
  }

  @override
  Future<void> cancelRefillReminder(
    String rxcui, {
    String cabinetId = 'default',
  }) async {
    refillCancelled.add('$cabinetId::$rxcui');
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
      expect(find.text('Set Reminder'), findsOneWidget);

      // 2. Open ReminderSheet from DrugCard and save default Morning (8:00 AM) reminder
      await tester.tap(find.text('Set Reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Medication Reminder'), findsOneWidget);
      expect(find.text('Every Day'), findsOneWidget);
      expect(find.text('Specific Days'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
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

      await tester.tap(find.text('Set Reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Specific Days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Reminder'));
      await tester.pumpAndSettle();

      final momId = provider.activeCabinetId;
      expect(notifs.scheduled.last, "$momId::1364430::Time for Mom's Eliquis");

      // 7. Add an OTC Supplement to Mom's cabinet and verify separated section + local-only privacy
      final vitD = await provider.addSupplement(
        name: 'Vitamin D3',
        dosage: '2000 IU',
        note: 'With breakfast',
      );
      expect(vitD, isNotNull);
      await tester.pumpAndSettle();
      expect(find.text('OTC & Supplements (1)'), findsOneWidget);
      expect(find.text('Vitamin D3'), findsOneWidget);
      expect(find.text('2000 IU • With breakfast'), findsOneWidget);

      // 8. Verify zero PII and zero OTC IDs ever sent to API (only numeric RxCUIs)
      for (final payload in api.recordedRxcuiPayloads) {
        for (final id in payload) {
          expect(RegExp(r'^\d+$').hasMatch(id), true, reason: 'Only numeric RxCUIs may leave device');
        }
      }

      // 9. Switch back to My Cabinet and verify original state is untouched (and Mom's OTC is isolated)
      await tester.tap(find.text("Mom's Cabinet (1)"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Cabinet'));
      await tester.pumpAndSettle();

      expect(find.text('My Medication Cabinet (1)'), findsOneWidget);
      expect(find.text('Vyvanse'), findsOneWidget);
      expect(find.text('Taken Today'), findsOneWidget);
      expect(find.text('Vitamin D3'), findsNothing);
    },
  );

  testWidgets(
    'Desktop Full-Width Smoke Test: Clean Header Smart Fallback KPIs & End-to-End Refill Tracker',
    (tester) async {
      // Wide desktop browser viewport (>= 960px)
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
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
              pricing: PricingInfo(
                estimatedSavingsPct: 84.0,
              ),
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

      // 1. Clean desktop header + sidebar + smart fallback (NADAC cost gap when no shortages/reminders)
      expect(find.text('WATCHED MEDS'), findsOneWidget);
      expect(find.text('1 Rx'), findsOneWidget);
      expect(find.text('GENERICS AVAILABLE'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.text('REFILLS DUE'), findsOneWidget);
      expect(find.text('Not Set'), findsOneWidget);
      expect(find.text('EST. GENERIC GAP'), findsOneWidget);
      expect(find.text('Up to 84%'), findsOneWidget);

      // 2. Open RefillSetupSheet from DrugCard and save default 30-day supply
      await tester.tap(find.text('Track Refill'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refill & Supply'), findsOneWidget);
      await tester.tap(find.text('Save Refill Tracker'));
      await tester.pumpAndSettle();

      expect(find.text('All Stocked'), findsOneWidget);
      expect(find.textContaining('Refill in 30d'), findsOneWidget);
      expect(notifs.refillScheduled.last, 'default::855333::Refill Reminder: Vyvanse');

      // 3. Simulate a prescription due in 3 days with 1 refill remaining -> verify KPI + Mark Refilled
      final now = DateTime.now();
      final dueSoonDate = RefillInfo.dateKey(
        DateTime(now.year, now.month, now.day - 27),
      );
      await provider.saveRefill(
        RefillInfo(
          rxcui: '855333',
          drugName: 'Vyvanse',
          lastFilledDate: dueSoonDate,
          daySupply: 30,
          remindDaysBefore: 5,
          refillsRemaining: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 Due'), findsOneWidget);
      expect(find.textContaining('Refill in 3d'), findsAtLeastNWidgets(1));
      expect(find.text('Compare Prices'), findsOneWidget);
      expect(find.text('Mark Refilled'), findsAtLeastNWidgets(1));

      // 4. Tap Mark Refilled -> resets to 30d, All Stocked, clears Refill-Due banner, and shows 0 left renewal tag
      await tester.tap(find.text('Mark Refilled').first);
      await tester.pumpAndSettle();

      expect(find.text('All Stocked'), findsOneWidget);
      expect(find.text('Compare Prices'), findsNothing);
      expect(find.textContaining('Refill in 30d'), findsOneWidget);
      expect(find.textContaining('0 left'), findsOneWidget);

      // 5. Smart fallback switches 4th KPI card to TODAY'S DOSES when a reminder is active
      await provider.saveReminder(
        const MedicationReminder(
          rxcui: '855333',
          drugName: 'Vyvanse',
          times: [ReminderTime(hour: 8, minute: 0)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("TODAY'S DOSES"), findsOneWidget);
      expect(find.text('0 of 1'), findsOneWidget);

      // 6. Smart fallback prioritizes FDA SHORTAGES over Today's Doses when a shortage drug is watched
      await provider.addDrug(
        Drug(
          rxcui: '1364430',
          brandName: 'Eliquis',
          genericName: 'apixaban',
          hasActiveShortage: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FDA SHORTAGES'), findsOneWidget);
      expect(find.text('1 Active'), findsOneWidget);

      // 6b. Tap footer Privacy & Terms links -> verify in-app policy sheets open cleanly
      await tester.ensureVisible(find.text('Privacy'));
      await tester.tap(find.text('Privacy'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy & Consumer Health Data Notice'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Terms'));
      await tester.tap(find.text('Terms'));
      await tester.pumpAndSettle();
      expect(find.text('Terms of Service'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 7. Verify zero refill/PII strings ever left the device
      for (final payload in api.recordedRxcuiPayloads) {
        for (final id in payload) {
          expect(RegExp(r'^\d+$').hasMatch(id), true);
        }
      }
    },
  );

  testWidgets(
    'DrugDetailScreen Smoke Test: Clean Patient-First Layout & Working Native Partner Links',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _SmokeStorageService();
      final api = _SmokeApiService();
      final notifs = _SmokeNotificationService();

      final lipitor = Drug(
        rxcui: '262095',
        brandName: 'Lipitor',
        genericName: 'atorvastatin calcium',
        hasApprovedGeneric: true,
        commercialGenericAvailable: true,
        substitutionStatus: 'auto_substitutable',
        verificationSources: const ['FDA Orange Book', 'DailyMed', 'CMS NADAC'],
        pricing: PricingInfo(
          brandNadacUnitPrice: 12.50,
          genericNadacUnitPrice: 0.15,
          estimatedSavingsPct: 98.0,
        ),
      );

      storage.cabinets = [
        PatientCabinet.emptyDefault(
          drugs: [lipitor],
          refills: {
            '262095': RefillInfo(
              rxcui: '262095',
              drugName: 'Lipitor',
              lastFilledDate: RefillInfo.todayKey(),
              daySupply: 30,
              remindDaysBefore: 5,
              refillsRemaining: 3,
            ),
          },
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
          child: MaterialApp(
            home: DrugDetailScreen(
              drug: lipitor,
              initialLocalPharmacies: const [
                {
                  'id': 1,
                  'business_name': 'Main Street Independent Pharmacy',
                  'phone': '(555) 234-5678',
                  'address': '123 Main St, Addison, TX 75001',
                  'transfer_url': 'https://mainstreetrx.com/transfer',
                  'tagline': 'Transparent cash prices & free local delivery',
                },
              ],
              initialPartners: const [
                {
                  'id': 'cost_plus_drugs',
                  'label': 'Cost Plus Drugs',
                  'url': 'https://www.costplusdrugs.com/medications/atorvastatin-10mg-tablet/',
                  'price_hint': 'from \$5.25',
                },
                {
                  'id': 'amazon_pharmacy',
                  'label': 'Amazon Pharmacy',
                  'url': 'https://pharmacy.amazon.com/s?k=Lipitor&tag=danglingdices-20',
                  'price_hint': null,
                },
                {
                  'id': 'singlecare',
                  'label': 'SingleCare Coupon',
                  'url': 'https://www.singlecare.com/prescription/lipitor',
                  'price_hint': null,
                },
                {
                  'id': 'goodrx',
                  'label': 'GoodRx Coupon',
                  'url': 'https://www.goodrx.com/lipitor',
                  'price_hint': null,
                },
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Removed clutter must not appear on the Drug Detail page
      expect(find.textContaining('2-Signal'), findsNothing);
      expect(find.textContaining('Verified using:'), findsNothing);
      expect(find.textContaining('RxCUI:'), findsNothing);

      // Essential patient-facing sections are present
      expect(find.text('Generic Option & Pharmacy Guidance'), findsOneWidget);
      expect(find.text('Prescription Refill & Supply'), findsOneWidget);
      expect(find.text('Compare Cash & Pharmacy Prices'), findsOneWidget);
      expect(find.text('Estimated Cost & Savings'), findsOneWidget);
      expect(find.text('Cost Plus Drugs (from \$5.25)'), findsOneWidget);
      expect(find.text('Amazon Pharmacy'), findsOneWidget);
      expect(find.text('SingleCare Coupon'), findsOneWidget);
      expect(find.text('GoodRx Coupon'), findsOneWidget);

      // Enter a local-only 5-digit ZIP code -> enriches client-side coupon links + labels + Maps button
      final zipField = find.widgetWithText(TextField, 'ZIP (optional)');
      expect(zipField, findsOneWidget);
      await tester.enterText(zipField, '75001');
      await tester.pumpAndSettle();
      expect(storage.localZip, '75001');
      expect(find.textContaining('Saved locally for 75001'), findsOneWidget);
      expect(find.textContaining('Est. 30-day generic cash range near 75001'), findsOneWidget);
      expect(find.text('SingleCare near 75001'), findsOneWidget);
      expect(find.text('GoodRx near 75001'), findsOneWidget);
      expect(find.text('Pharmacies near 75001'), findsOneWidget);
      expect(find.text('Main Street Independent Pharmacy'), findsOneWidget);
      expect(find.text('Sponsored Local Partner'), findsOneWidget);

      // Partner buttons are rendered via native url_launcher Link(target: LinkTarget.blank) with local ZIP
      final links = tester.widgetList<Link>(find.byType(Link)).toList();
      expect(links.length, greaterThanOrEqualTo(4));
      expect(
        links.any((l) => l.uri?.host == 'www.costplusdrugs.com' && l.target == LinkTarget.blank),
        isTrue,
      );
      expect(
        links.any((l) => l.uri?.host == 'pharmacy.amazon.com' && l.target == LinkTarget.blank),
        isTrue,
      );
      expect(
        links.any((l) => l.uri?.host == 'www.singlecare.com' && l.uri?.queryParameters['zip'] == '75001'),
        isTrue,
      );
      expect(
        links.any((l) => l.uri?.host == 'www.goodrx.com' && l.uri?.queryParameters['location'] == '75001'),
        isTrue,
      );
    },
  );
}
