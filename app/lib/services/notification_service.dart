import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/medication_reminder.dart';

class NotificationService {
  static const int _maxSlotsPerDrug = 8;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;
  bool _tzInitialized = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  void _ensureTimezone() {
    if (_tzInitialized) return;
    try {
      tzdata.initializeTimeZones();
      final offset = DateTime.now().timeZoneOffset;
      tz.Location? matched;
      for (final loc in tz.timeZoneDatabase.locations.values) {
        if (loc.currentTimeZone.offset == offset) {
          matched = loc;
          break;
        }
      }
      if (matched != null) {
        tz.setLocalLocation(matched);
      }
      _tzInitialized = true;
    } catch (e) {
      debugPrint('[NotificationService] Timezone init warning: $e');
    }
  }

  int _reminderNotificationId(String rxcui, int slotIndex) {
    final base = (rxcui.hashCode & 0x0FFFFFFF) % 1000000;
    return 100000 + base * 10 + (slotIndex % _maxSlotsPerDrug);
  }

  Future<void> initialize() async {
    if (kIsWeb || _isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          // Handle notification tap
        },
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('[NotificationService] Failed to initialize: $e');
    }
  }

  Future<void> showGenericLaunchNotification({
    required String drugName,
    String? genericName,
    double? savingsPct,
  }) async {
    if (kIsWeb) return;
    await initialize();

    final title = 'Generic Available: $drugName';
    final savingsText = savingsPct != null && savingsPct > 0
        ? 'with estimated ${savingsPct.toStringAsFixed(0)}% savings!'
        : 'now commercialized!';
    final body = 'Commercial generic ($genericName) is now distributed at retail pharmacies $savingsText';

    const androidDetails = AndroidNotificationDetails(
      'generic_launches',
      'Generic Launches',
      channelDescription: 'Notifications when commercial generic versions of watched drugs launch',
      importance: Importance.max,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _plugin.show(
        id: drugName.hashCode,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[NotificationService] Error showing notification: $e');
    }
  }

  Future<void> showShortageNotification({
    required String drugName,
    required String reason,
  }) async {
    if (kIsWeb) return;
    await initialize();

    final title = 'Shortage Alert: $drugName';
    final body = 'FDA reports a supply shortage for your watched medication: $reason';

    const androidDetails = AndroidNotificationDetails(
      'drug_shortages',
      'Drug Shortages',
      channelDescription: 'Alerts when supply shortages impact watched medications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const darwinDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _plugin.show(
        id: ('shortage_$drugName').hashCode,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[NotificationService] Error showing shortage alert: $e');
    }
  }

  /// Schedule daily repeating on-device alarms for a medication reminder.
  /// Uses AndroidScheduleMode.inexactAllowWhileIdle (Google Play compliant, zero special exact-alarm permission).
  Future<void> scheduleDailyMedicationReminder(MedicationReminder reminder) async {
    if (kIsWeb) return;
    await initialize();
    _ensureTimezone();

    // Always clear previous slots for this medication first
    await cancelMedicationReminders(reminder.rxcui);

    if (!reminder.enabled || reminder.times.isEmpty) return;

    // Request Android 13+ POST_NOTIFICATIONS runtime permission cleanly
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}

    const androidDetails = AndroidNotificationDetails(
      'medication_reminders',
      'Daily Medication Reminders',
      channelDescription: 'Private on-device daily reminders to take your scheduled prescriptions',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final now = tz.TZDateTime.now(tz.local);
    final slots = reminder.times.take(_maxSlotsPerDrug).toList();

    for (var i = 0; i < slots.length; i++) {
      final t = slots[i];
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      try {
        await _plugin.zonedSchedule(
          id: _reminderNotificationId(reminder.rxcui, i),
          title: reminder.notificationTitle,
          body: reminder.notificationBody,
          scheduledDate: scheduled,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (e) {
        debugPrint('[NotificationService] Error scheduling reminder slot $i: $e');
      }
    }
  }

  Future<void> cancelMedicationReminders(String rxcui) async {
    if (kIsWeb) return;
    await initialize();
    for (var i = 0; i < _maxSlotsPerDrug; i++) {
      try {
        await _plugin.cancel(id: _reminderNotificationId(rxcui, i));
      } catch (_) {}
    }
  }
}
