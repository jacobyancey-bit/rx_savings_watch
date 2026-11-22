import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/drug.dart';
import '../models/medication_reminder.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/web_push_service.dart';

class CabinetProvider extends ChangeNotifier {
  final StorageService _storageService;
  final NotificationService _notificationService;
  late ApiService _apiService;
  final Completer<void> _initCompleter = Completer<void>();

  List<Drug> _cabinet = [];
  Map<String, MedicationReminder> _reminders = {};
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _lastChecked;
  String? _syncError;
  int _lastNewAlertsCount = 0;
  bool _allowLaunchNotifs = true;
  bool _allowShortageNotifs = true;
  double _textScale = 1.0;

  CabinetProvider({
    StorageService? storageService,
    ApiService? apiService,
    NotificationService? notificationService,
  })  : _storageService = storageService ?? StorageService(),
        _apiService = apiService ?? ApiService(),
        _notificationService = notificationService ?? NotificationService() {
    _init();
  }

  List<Drug> get cabinet => List.unmodifiable(_cabinet);
  Map<String, MedicationReminder> get reminders => Map.unmodifiable(_reminders);
  MedicationReminder? reminderFor(String rxcui) => _reminders[rxcui];
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get lastChecked => _lastChecked;
  String? get syncError => _syncError;
  int get lastNewAlertsCount => _lastNewAlertsCount;
  String get serverUrl => _apiService.baseUrl;
  bool get allowLaunchNotifs => _allowLaunchNotifs;
  bool get allowShortageNotifs => _allowShortageNotifs;
  double get textScale => _textScale;

  String get textScaleLabel {
    if (_textScale >= 1.3) return 'Extra Large';
    if (_textScale >= 1.15) return 'Large';
    return 'Standard';
  }

  int get genericLaunchedCount =>
      _cabinet.where((d) => d.commercialGenericAvailable).length;

  int get shortageCount =>
      _cabinet.where((d) => d.hasActiveShortage).length;

  double get maxSavingsAvailable {
    double maxPct = 0.0;
    for (final d in _cabinet) {
      final s = d.pricing?.estimatedSavingsPct;
      if (s != null && s > maxPct) {
        maxPct = s;
      }
    }
    return maxPct;
  }

  bool isWatched(String rxcui) => _cabinet.any((d) => d.rxcui == rxcui);

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    final customUrl = await _storageService.getCustomServerUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      _apiService = ApiService(baseUrl: customUrl);
    }

    _allowLaunchNotifs = await _storageService.getAllowLaunchNotifications();
    _allowShortageNotifs = await _storageService.getAllowShortageNotifications();
    _textScale = await _storageService.getTextScale();

    _cabinet = await _storageService.loadCabinet();
    _reminders = await _storageService.loadReminders();
    _lastChecked = await _storageService.getLastCheckedTimestamp();
    await WebPushService.syncWatchedRxcuis(_cabinet.map((d) => d.rxcui).toList());
    _isLoading = false;
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
    notifyListeners();

    // Auto-sync cabinet if items exist
    if (_cabinet.isNotEmpty) {
      await syncCabinet();
    }
  }

  Future<void> setServerUrl(String url) async {
    await _storageService.saveCustomServerUrl(url);
    _apiService = ApiService(baseUrl: url);
    notifyListeners();
  }

  Future<void> setAllowLaunchNotifs(bool allow) async {
    _allowLaunchNotifs = allow;
    await _storageService.setAllowLaunchNotifications(allow);
    notifyListeners();
  }

  Future<void> setAllowShortageNotifs(bool allow) async {
    _allowShortageNotifs = allow;
    await _storageService.setAllowShortageNotifications(allow);
    notifyListeners();
  }

  Future<void> setTextScale(double scale) async {
    _textScale = scale.clamp(1.0, 1.4);
    await _storageService.saveTextScale(_textScale);
    notifyListeners();
  }

  Future<void> cycleTextScale() async {
    if (_textScale < 1.15) {
      await setTextScale(1.18);
    } else if (_textScale < 1.3) {
      await setTextScale(1.35);
    } else {
      await setTextScale(1.0);
    }
  }

  Future<void> clearAllData() async {
    for (final rxcui in _reminders.keys) {
      await _notificationService.cancelMedicationReminders(rxcui);
    }
    _cabinet = [];
    _reminders = {};
    _lastChecked = null;
    _syncError = null;
    _lastNewAlertsCount = 0;
    await _storageService.clearAllLocalData();
    await WebPushService.syncWatchedRxcuis(const []);
    notifyListeners();
  }

  Future<void> addDrug(Drug drug) async {
    if (isWatched(drug.rxcui)) return;

    _cabinet.add(drug);
    await _storageService.saveCabinet(_cabinet);
    await WebPushService.syncWatchedRxcuis(_cabinet.map((d) => d.rxcui).toList());
    notifyListeners();

    // Trigger sync for this new drug
    await syncCabinet();
  }

  Future<void> removeDrug(String rxcui) async {
    _cabinet.removeWhere((d) => d.rxcui == rxcui);
    if (_reminders.remove(rxcui) != null) {
      await _storageService.saveReminders(_reminders);
      await _notificationService.cancelMedicationReminders(rxcui);
    }
    await _storageService.saveCabinet(_cabinet);
    await WebPushService.syncWatchedRxcuis(_cabinet.map((d) => d.rxcui).toList());
    notifyListeners();
  }

  Future<void> saveReminder(MedicationReminder reminder) async {
    _reminders[reminder.rxcui] = reminder;
    await _storageService.saveReminders(_reminders);
    await _notificationService.scheduleDailyMedicationReminder(reminder);
    notifyListeners();
  }

  Future<void> deleteReminder(String rxcui) async {
    _reminders.remove(rxcui);
    await _storageService.saveReminders(_reminders);
    await _notificationService.cancelMedicationReminders(rxcui);
    notifyListeners();
  }

  Future<void> toggleTakenToday(String rxcui) async {
    final existing = _reminders[rxcui];
    if (existing == null) return;
    final updated = existing.isTakenToday()
        ? existing.copyWith(clearTakenDate: true)
        : existing.copyWith(takenDate: MedicationReminder.todayKey());
    _reminders[rxcui] = updated;
    await _storageService.saveReminders(_reminders);
    notifyListeners();
  }

  /// Import medications from another device by RxCUI list (zero-PII transfer).
  /// Uses the anonymous, k-anonymity-chaffed check-updates endpoint to hydrate
  /// each drug's canonical FDA/CMS status, then saves locally on this device.
  Future<int> importRxcuis(List<String> rxcuis) async {
    await _initCompleter.future;
    final newRxcuis = rxcuis
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty && !isWatched(r))
        .toSet()
        .toList();

    if (newRxcuis.isEmpty) return 0;

    final response = await _apiService.checkUpdates(
      rxcuis: newRxcuis,
    );

    final List returnedDrugs = response['drugs'] as List? ?? [];
    int addedCount = 0;

    for (final item in returnedDrugs) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final drug = Drug.fromJson(map);
        if (drug.rxcui.isNotEmpty && !isWatched(drug.rxcui)) {
          _cabinet.add(drug);
          addedCount++;
        }
      }
    }

    if (addedCount > 0) {
      final checkedAt = response['checked_at'] as String? ?? DateTime.now().toIso8601String();
      _lastChecked = checkedAt;
      await _storageService.saveCabinet(_cabinet);
      await _storageService.saveLastCheckedTimestamp(checkedAt);
      await WebPushService.syncWatchedRxcuis(_cabinet.map((d) => d.rxcui).toList());
      notifyListeners();
    }

    return addedCount;
  }

  /// Sync cabinet medications anonymously with server
  Future<void> syncCabinet() async {
    if (_cabinet.isEmpty || _isSyncing) return;

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final rxcuis = _cabinet.map((d) => d.rxcui).toList();
      final response = await _apiService.checkUpdates(
        rxcuis: rxcuis,
        lastChecked: _lastChecked,
      );

      final List updatedDrugsJson = response['drugs'] as List? ?? [];
      final checkedAt = response['checked_at'] as String? ?? DateTime.now().toIso8601String();
      _lastNewAlertsCount = response['updates_found'] as int? ?? 0;

      // Update cabinet items with fresh status
      final updatedCabinet = <Drug>[];
      for (final existing in _cabinet) {
        Map<String, dynamic>? match;
        for (final item in updatedDrugsJson) {
          if (item is Map && item['rxcui']?.toString() == existing.rxcui) {
            match = Map<String, dynamic>.from(item);
            break;
          }
        }

        if (match != null) {
          final wasCommercial = existing.commercialGenericAvailable;
          final wasShortage = existing.hasActiveShortage;

          final updated = existing.copyWithUpdate(match);
          updatedCabinet.add(updated);

          // Check if newly commercialized -> trigger notification
          if (!wasCommercial && updated.commercialGenericAvailable && _allowLaunchNotifs) {
            await _notificationService.showGenericLaunchNotification(
              drugName: updated.displayName,
              genericName: updated.genericName,
              savingsPct: updated.pricing?.estimatedSavingsPct,
            );
          }

          // Check if newly entered shortage -> trigger notification
          if (!wasShortage && updated.hasActiveShortage && _allowShortageNotifs) {
            final reason = updated.activeShortageDetails.isNotEmpty && updated.activeShortageDetails[0]['reason'] != null
                ? updated.activeShortageDetails[0]['reason'] as String
                : 'Demand increase or manufacturing delay';
            await _notificationService.showShortageNotification(
              drugName: updated.displayName,
              reason: reason,
            );
          }
        } else {
          updatedCabinet.add(existing);
        }
      }

      _cabinet = updatedCabinet;
      _lastChecked = checkedAt;

      await _storageService.saveCabinet(_cabinet);
      await _storageService.saveLastCheckedTimestamp(checkedAt);
    } catch (e) {
      _syncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
