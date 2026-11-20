import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _isInitialized = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (_isInitialized) return;

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
}
