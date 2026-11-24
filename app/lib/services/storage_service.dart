import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drug.dart';
import '../models/medication_reminder.dart';
import '../models/patient_cabinet.dart';

class StorageService {
  static const String _cabinetKey = 'rx_savings_cabinet_drugs_v1';
  static const String _remindersKey = 'rx_savings_reminders_v1';
  static const String _cabinetsKey = 'rx_savings_cabinets_v2';
  static const String _activeCabinetIdKey = 'rx_savings_active_cabinet_id_v2';
  static const String _lastCheckedKey = 'rx_savings_last_checked_timestamp';
  static const String _serverUrlKey = 'rx_savings_custom_server_url';
  static const String _allowLaunchNotifsKey = 'rx_savings_allow_launch_notifs';
  static const String _allowShortageNotifsKey = 'rx_savings_allow_shortage_notifs';
  static const String _textScaleKey = 'rx_savings_text_scale_v1';
  static const String _localZipKey = 'rx_savings_local_zip_v1';

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

  /// Strictly on-device 5-digit ZIP code for client-side local pharmacy coupon links.
  /// Never transmitted to Rx Savings Watch servers.
  Future<String?> getLocalZipCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_localZipKey);
  }

  Future<void> saveLocalZipCode(String? zip) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = (zip ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length == 5) {
      await prefs.setString(_localZipKey, clean);
    } else {
      await prefs.remove(_localZipKey);
    }
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

  Future<List<PatientCabinet>> loadCabinets() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_cabinetsKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List decoded = jsonDecode(jsonString) as List;
        final list = decoded
            .whereType<Map>()
            .map((m) => PatientCabinet.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    // Seamless zero-loss migration from single-cabinet storage
    final legacyDrugs = await loadCabinet();
    final legacyReminders = await loadReminders();
    final migrated = [
      PatientCabinet.emptyDefault(
        drugs: legacyDrugs,
        reminders: legacyReminders,
      ),
    ];
    if (legacyDrugs.isNotEmpty || legacyReminders.isNotEmpty) {
      await saveCabinets(migrated);
    }
    return migrated;
  }

  Future<void> saveCabinets(List<PatientCabinet> cabinets) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = cabinets.map((c) => c.toJson()).toList();
    await prefs.setString(_cabinetsKey, jsonEncode(encoded));
  }

  Future<String> getActiveCabinetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeCabinetIdKey) ?? PatientCabinet.defaultId;
  }

  Future<void> saveActiveCabinetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeCabinetIdKey, id);
  }

  Future<void> clearAllLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cabinetsKey);
    await prefs.remove(_activeCabinetIdKey);
    await prefs.remove(_cabinetKey);
    await prefs.remove(_remindersKey);
    await prefs.remove(_lastCheckedKey);
  }
}
