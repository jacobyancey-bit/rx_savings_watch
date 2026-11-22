import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drug.dart';
import '../models/medication_reminder.dart';

class StorageService {
  static const String _cabinetKey = 'rx_savings_cabinet_drugs_v1';
  static const String _remindersKey = 'rx_savings_reminders_v1';
  static const String _lastCheckedKey = 'rx_savings_last_checked_timestamp';
  static const String _serverUrlKey = 'rx_savings_custom_server_url';
  static const String _allowLaunchNotifsKey = 'rx_savings_allow_launch_notifs';
  static const String _allowShortageNotifsKey = 'rx_savings_allow_shortage_notifs';
  static const String _textScaleKey = 'rx_savings_text_scale_v1';

  Future<List<Drug>> loadCabinet() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_cabinetKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List decoded = jsonDecode(jsonString);
      return decoded.map((item) => Drug.fromJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveCabinet(List<Drug> drugs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = drugs.map((d) => d.toJson()).toList();
    await prefs.setString(_cabinetKey, jsonEncode(jsonList));
  }

  Future<String?> getLastCheckedTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastCheckedKey);
  }

  Future<void> saveLastCheckedTimestamp(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckedKey, timestamp);
  }

  Future<String?> getCustomServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey);
  }

  Future<void> saveCustomServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  Future<bool> getAllowLaunchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowLaunchNotifsKey) ?? true;
  }

  Future<void> setAllowLaunchNotifications(bool allow) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowLaunchNotifsKey, allow);
  }

  Future<bool> getAllowShortageNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_allowShortageNotifsKey) ?? true;
  }

  Future<void> setAllowShortageNotifications(bool allow) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allowShortageNotifsKey, allow);
  }

  Future<double> getTextScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_textScaleKey) ?? 1.0;
  }

  Future<void> saveTextScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, scale);
  }

  Future<Map<String, MedicationReminder>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_remindersKey);
    if (jsonString == null || jsonString.isEmpty) {
      return {};
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final result = <String, MedicationReminder>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          result[entry.key] = MedicationReminder.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveReminders(Map<String, MedicationReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = reminders.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_remindersKey, jsonEncode(encoded));
  }

  Future<void> clearAllLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cabinetKey);
    await prefs.remove(_remindersKey);
    await prefs.remove(_lastCheckedKey);
  }
}
