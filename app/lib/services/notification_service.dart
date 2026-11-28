import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/medication_reminder.dart';
import '../models/refill_info.dart';

class NotificationService {
  static const int _maxSlotsPerDrug = 32;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;
  bool _tzInitialized = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Resolves the device's real IANA timezone (e.g. `America/New_York`) so daily/monthly
  /// reminders stay at the same wall-clock time across DST transitions.
  ///
  /// Matching by the current UTC offset alone is NOT safe: for US Eastern in winter (UTC-5)
  /// the first offset match is `America/Bogota`, which never observes DST, so reminders would
  /// silently shift by one hour every March and November.
  Future<void> _ensureTimezone() async {
    if (_tzInitialized) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _tzInitialized = true;
    } catch (e) {
      // Fallback: keep the timezone package default (UTC) rather than guessing a zone by
      // offset, and retry on the next scheduling call.
      debugPrint('[NotificationService] Timezone init warning: $e');
    }
  }

  int _reminderNotificationId(
    String rxcui,
    int slotIndex, {
    String cabinetId = 'default',
  }) {
    final key = cabinetId == 'default' ? rxcui : '$cabinetId::$rxcui';
    final base = (key.hashCode & 0x00FFFFFF) % 500000;
    return 100000 + base * 40 + (slotIndex % _maxSlotsPerDrug);
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
  Future<void> scheduleDailyMedicationReminder(
    MedicationReminder reminder, {
    String cabinetId = 'default',
  }) async {
    if (kIsWeb) return;
    await initialize();
    await _ensureTimezone();

    // Always clear previous slots for this medication first
    await cancelMedicationReminders(reminder.rxcui, cabinetId: cabinetId);

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
    int slotIndex = 0;

    Future<void> scheduleSlot(tz.TZDateTime when, DateTimeComponents matchMode) async {
      if (slotIndex >= _maxSlotsPerDrug) return;
      final id = _reminderNotificationId(reminder.rxcui, slotIndex++, cabinetId: cabinetId);
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: reminder.notificationTitle,
          body: reminder.notificationBody,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: matchMode,
        );
      } catch (e) {
        debugPrint('[NotificationService] Error scheduling reminder slot $slotIndex: $e');
      }
    }

    switch (reminder.frequency) {
      case ReminderFrequency.daily:
        for (final t in reminder.times) {
          var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
          if (scheduled.isBefore(now)) {
            scheduled = scheduled.add(const Duration(days: 1));
          }
          await scheduleSlot(scheduled, DateTimeComponents.time);
        }
        break;
      case ReminderFrequency.specificDays:
        for (final weekday in reminder.normalizedWeekdays) {
          for (final t in reminder.times) {
            var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
            var daysAhead = (weekday - scheduled.weekday) % 7;
            if (daysAhead < 0) daysAhead += 7;
            scheduled = scheduled.add(Duration(days: daysAhead));
            if (scheduled.isBefore(now)) {
              scheduled = scheduled.add(const Duration(days: 7));
            }
            await scheduleSlot(scheduled, DateTimeComponents.dayOfWeekAndTime);
          }
        }
        break;
      case ReminderFrequency.monthly:
        final dom = reminder.dayOfMonth.clamp(1, 28);
        for (final t in reminder.times) {
          var scheduled = tz.TZDateTime(tz.local, now.year, now.month, dom, t.hour, t.minute);
          if (scheduled.isBefore(now)) {
            final nextMonth = now.month == 12 ? 1 : now.month + 1;
            final nextYear = now.month == 12 ? now.year + 1 : now.year;
            scheduled = tz.TZDateTime(tz.local, nextYear, nextMonth, dom, t.hour, t.minute);
          }
          await scheduleSlot(scheduled, DateTimeComponents.dayOfMonthAndTime);
        }
        break;
    }
  }

  Future<void> cancelMedicationReminders(
    String rxcui, {
    String cabinetId = 'default',
  }) async {
    if (kIsWeb) return;
    await initialize();
    for (var i = 0; i < _maxSlotsPerDrug; i++) {
      try {
        await _plugin.cancel(id: _reminderNotificationId(rxcui, i, cabinetId: cabinetId));
      } catch (_) {}
    }
  }

  int _refillNotificationId(String rxcui, {String cabinetId = 'default'}) {
    final key = cabinetId == 'default' ? 'refill::$rxcui' : 'refill::$cabinetId::$rxcui';
    final base = (key.hashCode & 0x00FFFFFF) % 400000;
    return 600000 + base;
  }

  Future<void> scheduleRefillReminder(
    RefillInfo refill, {
    String cabinetId = 'default',
  }) async {
    if (kIsWeb) return;
    await initialize();
    await _ensureTimezone();

    await cancelRefillReminder(refill.rxcui, cabinetId: cabinetId);
    if (!refill.enabled) return;

    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}

    final targetDate = refill.reminderDate;
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      targetDate.year,
      targetDate.month,
      targetDate.day,
      9,
      0,
    );
    if (scheduled.isBefore(now)) {
      // If reminder date has already passed, schedule 1 minute from now if not yet overdue by > 14 days
      if (refill.daysRemaining() < -14) return;
      scheduled = now.add(const Duration(minutes: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'refill_reminders',
      'Prescription Refill Reminders',
      channelDescription: 'Private on-device alerts before your prescription supply runs out',
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
      await _plugin.zonedSchedule(
        id: _refillNotificationId(refill.rxcui, cabinetId: cabinetId),
        title: refill.notificationTitle,
        body: refill.notificationBody,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('[NotificationService] Error scheduling refill alert: $e');
    }
  }

  Future<void> cancelRefillReminder(
    String rxcui, {
    String cabinetId = 'default',
  }) async {
    if (kIsWeb) return;
    await initialize();
    try {
      await _plugin.cancel(id: _refillNotificationId(rxcui, cabinetId: cabinetId));
    } catch (_) {}
  }
}
