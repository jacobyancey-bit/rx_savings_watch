import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/drug.dart';
import '../models/medication_reminder.dart';
import '../models/otc_supplement.dart';
import '../models/patient_cabinet.dart';
import '../models/refill_info.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/web_push_service.dart';

class CabinetProvider extends ChangeNotifier {
  final StorageService _storageService;
  final NotificationService _notificationService;
  late ApiService _apiService;
  final Completer<void> _initCompleter = Completer<void>();

  List<PatientCabinet> _cabinets = [PatientCabinet.emptyDefault()];
  String _activeCabinetId = PatientCabinet.defaultId;
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _lastChecked;
  String? _syncError;
  int _lastNewAlertsCount = 0;
  bool _allowLaunchNotifs = true;
  bool _allowShortageNotifs = true;
  double _textScale = 1.0;
  String? _localZipCode;

  CabinetProvider({
    StorageService? storageService,
    ApiService? apiService,
    NotificationService? notificationService,
  })  : _storageService = storageService ?? StorageService(),
        _apiService = apiService ?? ApiService(),
        _notificationService = notificationService ?? NotificationService() {
    _init();
  }

  List<PatientCabinet> get cabinets => List.unmodifiable(_cabinets);

  PatientCabinet get activeCabinet {
    for (final c in _cabinets) {
      if (c.id == _activeCabinetId) return c;
    }
    return _cabinets.first;
  }

  String get activeCabinetId => activeCabinet.id;
  bool get hasMultipleCabinets => _cabinets.length > 1;
  List<Drug> get cabinet => List.unmodifiable(activeCabinet.drugs);
  List<OtcSupplement> get supplements => List.unmodifiable(activeCabinet.supplements);
  Map<String, MedicationReminder> get reminders => Map.unmodifiable(activeCabinet.reminders);
  MedicationReminder? reminderFor(String rxcui) => activeCabinet.reminders[rxcui];
  Map<String, RefillInfo> get refills => Map.unmodifiable(activeCabinet.refills);
  RefillInfo? refillFor(String rxcui) => activeCabinet.refills[rxcui];

  int get refillsTrackedCount => activeCabinet.refills.length;

  int get refillsDueCount =>
      activeCabinet.refills.values.where((r) => r.enabled && r.isDueOrOverdue()).length;

  RefillInfo? get nextRefillDue {
    final tracked = activeCabinet.refills.values.where((r) => r.enabled).toList();
    if (tracked.isEmpty) return null;
    tracked.sort((a, b) => a.daysRemaining().compareTo(b.daysRemaining()));
    return tracked.first;
  }

  int get enabledRemindersCount =>
      activeCabinet.reminders.values.where((r) => r.enabled).length;

  int get takenTodayCount =>
      activeCabinet.reminders.values.where((r) => r.enabled && r.isTakenToday()).length;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get lastChecked => _lastChecked;
  String? get syncError => _syncError;
  int get lastNewAlertsCount => _lastNewAlertsCount;
  String get serverUrl => _apiService.baseUrl;
  bool get allowLaunchNotifs => _allowLaunchNotifs;
  bool get allowShortageNotifs => _allowShortageNotifs;
  double get textScale => _textScale;
  String? get localZipCode => _localZipCode;

  String get textScaleLabel {
    if (_textScale >= 1.3) return 'Extra Large';
    if (_textScale >= 1.15) return 'Large';
    return 'Standard';
  }

  int get genericLaunchedCount =>
      activeCabinet.drugs.where((d) => d.commercialGenericAvailable).length;

  int get shortageCount =>
      activeCabinet.drugs.where((d) => d.hasActiveShortage).length;

  double get maxSavingsAvailable {
    double maxPct = 0.0;
    for (final d in activeCabinet.drugs) {
      final s = d.pricing?.estimatedSavingsPct;
      if (s != null && s > maxPct) {
        maxPct = s;
      }
    }
    return maxPct;
  }

  bool isWatched(String rxcui) => activeCabinet.drugs.any((d) => d.rxcui == rxcui);

  /// Deduplicated anonymous RxCUIs across all local cabinets (zero cabinet names sent).
  List<String> _allWatchedRxcuis() {
    final set = <String>{};
    for (final c in _cabinets) {
      for (final d in c.drugs) {
        if (d.rxcui.isNotEmpty) set.add(d.rxcui);
      }
    }
    return set.toList();
  }

  void _replaceCabinet(PatientCabinet updated) {
    final idx = _cabinets.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) {
      _cabinets[idx] = updated;
    }
  }

  Future<void> _persistCabinets() async {
    await _storageService.saveCabinets(_cabinets);
    await WebPushService.syncWatchedRxcuis(_allWatchedRxcuis());
  }

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
    _localZipCode = await _storageService.getLocalZipCode();

    final loadedCabinets = await _storageService.loadCabinets();
    _cabinets = loadedCabinets.isNotEmpty ? loadedCabinets : [PatientCabinet.emptyDefault()];
    final savedActiveId = await _storageService.getActiveCabinetId();
    _activeCabinetId = _cabinets.any((c) => c.id == savedActiveId)
        ? savedActiveId
        : _cabinets.first.id;

    _lastChecked = await _storageService.getLastCheckedTimestamp();
    await WebPushService.syncWatchedRxcuis(_allWatchedRxcuis());
    _isLoading = false;
    if (!_initCompleter.isCompleted) {
      _initCompleter.complete();
    }
    notifyListeners();

    // Auto-sync active cabinet if items exist
    if (activeCabinet.drugs.isNotEmpty) {
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

  /// Saves an optional 5-digit ZIP code strictly on-device (never sent to server).
  Future<void> setLocalZipCode(String? zip) async {
    final clean = (zip ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    _localZipCode = clean.length == 5 ? clean : null;
    await _storageService.saveLocalZipCode(_localZipCode);
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

  Future<void> switchCabinet(String cabinetId) async {
    if (!_cabinets.any((c) => c.id == cabinetId) || _activeCabinetId == cabinetId) return;
    _activeCabinetId = cabinetId;
    _syncError = null;
    await _storageService.saveActiveCabinetId(cabinetId);
    notifyListeners();
  }

  Future<PatientCabinet?> createCabinet({
    required String name,
    int? colorValue,
  }) async {
    if (_cabinets.length >= PatientCabinet.maxCabinets) return null;
    final cleanName = PatientCabinet.sanitizeName(name, fallback: '');
    if (cleanName.isEmpty) return null;

    final id = 'cab_${DateTime.now().microsecondsSinceEpoch}';
    final created = PatientCabinet(
      id: id,
      name: cleanName,
      colorValue: PatientCabinet.sanitizeColor(colorValue),
    );
    _cabinets.add(created);
    _activeCabinetId = created.id;
    await _storageService.saveActiveCabinetId(created.id);
    await _persistCabinets();
    notifyListeners();
    return created;
  }

  Future<void> renameCabinet(
    String cabinetId, {
    required String name,
    int? colorValue,
  }) async {
    final idx = _cabinets.indexWhere((c) => c.id == cabinetId);
    if (idx < 0) return;

    final current = _cabinets[idx];
    final cleanName = PatientCabinet.sanitizeName(name, fallback: current.name);
    final updatedReminders = <String, MedicationReminder>{};
    final newLabel = current.isDefault ? null : cleanName;

    for (final entry in current.reminders.entries) {
      final updatedRem = newLabel == null
          ? entry.value.copyWith(clearCabinetLabel: true)
          : entry.value.copyWith(cabinetLabel: newLabel);
      updatedReminders[entry.key] = updatedRem;
      if (updatedRem.enabled) {
        await _notificationService.scheduleDailyMedicationReminder(
          updatedRem,
          cabinetId: current.id,
        );
      }
    }

    final updatedRefills = <String, RefillInfo>{};
    for (final entry in current.refills.entries) {
      final updatedRefill = newLabel == null
          ? entry.value.copyWith(clearCabinetLabel: true)
          : entry.value.copyWith(cabinetLabel: newLabel);
      updatedRefills[entry.key] = updatedRefill;
      if (updatedRefill.enabled) {
        await _notificationService.scheduleRefillReminder(
          updatedRefill,
          cabinetId: current.id,
        );
      }
    }

    _cabinets[idx] = current.copyWith(
      name: cleanName,
      colorValue: colorValue,
      reminders: updatedReminders,
      refills: updatedRefills,
    );
    await _persistCabinets();
    notifyListeners();
  }

  Future<bool> deleteCabinet(String cabinetId) async {
    if (_cabinets.length <= 1) return false;
    final idx = _cabinets.indexWhere((c) => c.id == cabinetId);
    if (idx < 0) return false;

    final target = _cabinets[idx];
    for (final rxcui in target.reminders.keys) {
      await _notificationService.cancelMedicationReminders(rxcui, cabinetId: target.id);
    }
    for (final rxcui in target.refills.keys) {
      await _notificationService.cancelRefillReminder(rxcui, cabinetId: target.id);
    }

    _cabinets.removeAt(idx);
    if (_activeCabinetId == cabinetId) {
      _activeCabinetId = _cabinets.first.id;
      await _storageService.saveActiveCabinetId(_activeCabinetId);
    }
    await _persistCabinets();
    notifyListeners();
    return true;
  }

  Future<void> clearActiveCabinet() async {
    final current = activeCabinet;
    for (final rxcui in current.reminders.keys) {
      await _notificationService.cancelMedicationReminders(rxcui, cabinetId: current.id);
    }
    for (final rxcui in current.refills.keys) {
      await _notificationService.cancelRefillReminder(rxcui, cabinetId: current.id);
    }
    _replaceCabinet(current.copyWith(
      drugs: const [],
      supplements: const [],
      reminders: const {},
      refills: const {},
    ));
    _syncError = null;
    _lastNewAlertsCount = 0;
    await _persistCabinets();
    notifyListeners();
  }

  Future<void> clearAllData() async {
    for (final cab in _cabinets) {
      for (final rxcui in cab.reminders.keys) {
        await _notificationService.cancelMedicationReminders(rxcui, cabinetId: cab.id);
      }
      for (final rxcui in cab.refills.keys) {
        await _notificationService.cancelRefillReminder(rxcui, cabinetId: cab.id);
      }
    }
    _cabinets = [PatientCabinet.emptyDefault()];
    _activeCabinetId = PatientCabinet.defaultId;
    _localZipCode = null;
    _lastChecked = null;
    _syncError = null;
    _lastNewAlertsCount = 0;
    await _storageService.clearAllLocalData();
    await WebPushService.syncWatchedRxcuis(const []);
    notifyListeners();
  }

  Future<void> addDrug(Drug drug) async {
    if (isWatched(drug.rxcui)) return;

    final current = activeCabinet;
    final nextDrugs = List<Drug>.from(current.drugs)..add(drug);
    _replaceCabinet(current.copyWith(drugs: nextDrugs));
    await _persistCabinets();
    notifyListeners();

    // Trigger sync for this new drug
    await syncCabinet();
  }

  Future<void> removeDrug(String rxcui) async {
    final current = activeCabinet;
    final nextDrugs = current.drugs.where((d) => d.rxcui != rxcui).toList();
    final nextReminders = Map<String, MedicationReminder>.from(current.reminders);
    if (nextReminders.remove(rxcui) != null) {
      await _notificationService.cancelMedicationReminders(rxcui, cabinetId: current.id);
    }
    final nextRefills = Map<String, RefillInfo>.from(current.refills);
    if (nextRefills.remove(rxcui) != null) {
      await _notificationService.cancelRefillReminder(rxcui, cabinetId: current.id);
    }
    _replaceCabinet(current.copyWith(
      drugs: nextDrugs,
      reminders: nextReminders,
      refills: nextRefills,
    ));
    await _persistCabinets();
    notifyListeners();
  }

  /// Adds an OTC / Supplement strictly on-device (never sent to server or push).
  Future<OtcSupplement?> addSupplement({
    required String name,
    String? dosage,
    String? note,
  }) async {
    final current = activeCabinet;
    if (current.supplements.length >= OtcSupplement.maxPerCabinet) return null;

    final cleanName = OtcSupplement.sanitizeText(name, OtcSupplement.maxNameLength);
    if (cleanName.isEmpty) return null;

    final cleanDosage = dosage != null
        ? OtcSupplement.sanitizeText(dosage, OtcSupplement.maxDosageLength)
        : '';
    final cleanNote = note != null
        ? OtcSupplement.sanitizeText(note, OtcSupplement.maxNoteLength)
        : '';

    final created = OtcSupplement(
      id: 'otc_${DateTime.now().microsecondsSinceEpoch}',
      name: cleanName,
      dosage: cleanDosage.isNotEmpty ? cleanDosage : null,
      note: cleanNote.isNotEmpty ? cleanNote : null,
    );

    final nextSupps = List<OtcSupplement>.from(current.supplements)..add(created);
    _replaceCabinet(current.copyWith(supplements: nextSupps));
    await _storageService.saveCabinets(_cabinets);
    notifyListeners();
    return created;
  }

  Future<void> removeSupplement(String supplementId) async {
    final current = activeCabinet;
    final nextSupps = current.supplements.where((s) => s.id != supplementId).toList();
    final nextReminders = Map<String, MedicationReminder>.from(current.reminders);
    if (nextReminders.remove(supplementId) != null) {
      await _notificationService.cancelMedicationReminders(supplementId, cabinetId: current.id);
    }
    _replaceCabinet(current.copyWith(supplements: nextSupps, reminders: nextReminders));
    await _storageService.saveCabinets(_cabinets);
    notifyListeners();
  }

  Future<void> saveReminder(MedicationReminder reminder) async {
    final current = activeCabinet;
    final labeled = current.isDefault
        ? reminder.copyWith(clearCabinetLabel: true)
        : reminder.copyWith(cabinetLabel: current.name);
    final nextReminders = Map<String, MedicationReminder>.from(current.reminders)
      ..[labeled.rxcui] = labeled;
    _replaceCabinet(current.copyWith(reminders: nextReminders));
    await _storageService.saveCabinets(_cabinets);
    await _notificationService.scheduleDailyMedicationReminder(
      labeled,
      cabinetId: current.id,
    );
    notifyListeners();
  }

  Future<void> deleteReminder(String rxcui) async {
    final current = activeCabinet;
    final nextReminders = Map<String, MedicationReminder>.from(current.reminders)
      ..remove(rxcui);
    _replaceCabinet(current.copyWith(reminders: nextReminders));
    await _storageService.saveCabinets(_cabinets);
    await _notificationService.cancelMedicationReminders(rxcui, cabinetId: current.id);
    notifyListeners();
  }

  Future<void> toggleTakenToday(String rxcui) async {
    final current = activeCabinet;
    final existing = current.reminders[rxcui];
    if (existing == null) return;
    final updated = existing.isTakenToday()
        ? existing.copyWith(clearTakenDate: true)
        : existing.copyWith(takenDate: MedicationReminder.todayKey());
    final nextReminders = Map<String, MedicationReminder>.from(current.reminders)
      ..[rxcui] = updated;
    _replaceCabinet(current.copyWith(reminders: nextReminders));
    await _storageService.saveCabinets(_cabinets);
    notifyListeners();
  }

  Future<void> saveRefill(RefillInfo refill) async {
    final current = activeCabinet;
    final labeled = current.isDefault
        ? refill.copyWith(clearCabinetLabel: true)
        : refill.copyWith(cabinetLabel: current.name);
    final nextRefills = Map<String, RefillInfo>.from(current.refills)
      ..[labeled.rxcui] = labeled;
    _replaceCabinet(current.copyWith(refills: nextRefills));
    await _storageService.saveCabinets(_cabinets);
    await _notificationService.scheduleRefillReminder(
      labeled,
      cabinetId: current.id,
    );
    notifyListeners();
  }

  Future<void> deleteRefill(String rxcui) async {
    final current = activeCabinet;
    final nextRefills = Map<String, RefillInfo>.from(current.refills)..remove(rxcui);
    _replaceCabinet(current.copyWith(refills: nextRefills));
    await _storageService.saveCabinets(_cabinets);
    await _notificationService.cancelRefillReminder(rxcui, cabinetId: current.id);
    notifyListeners();
  }

  Future<void> markRefilledToday(String rxcui, {DateTime? now}) async {
    final current = activeCabinet;
    final existing = current.refills[rxcui];
    if (existing == null) return;
    final updated = existing.markRefilledToday(now);
    final nextRefills = Map<String, RefillInfo>.from(current.refills)
      ..[rxcui] = updated;
    _replaceCabinet(current.copyWith(refills: nextRefills));
    await _storageService.saveCabinets(_cabinets);
    await _notificationService.scheduleRefillReminder(
      updated,
      cabinetId: current.id,
    );
    notifyListeners();
  }

  /// Import medications from another device by RxCUI list (zero-PII transfer)
  /// directly into the currently active cabinet.
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

    final current = activeCabinet;
    final nextDrugs = List<Drug>.from(current.drugs);

    for (final item in returnedDrugs) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final drug = Drug.fromJson(map);
        if (drug.rxcui.isNotEmpty && !nextDrugs.any((d) => d.rxcui == drug.rxcui)) {
          nextDrugs.add(drug);
          addedCount++;
        }
      }
    }

    if (addedCount > 0) {
      final checkedAt = response['checked_at'] as String? ?? DateTime.now().toIso8601String();
      _lastChecked = checkedAt;
      _replaceCabinet(current.copyWith(drugs: nextDrugs));
      await _storageService.saveLastCheckedTimestamp(checkedAt);
      await _persistCabinets();
      notifyListeners();
    }

    return addedCount;
  }

  /// Sync active cabinet medications anonymously with server (only RxCUIs sent).
  Future<void> syncCabinet() async {
    final targetId = activeCabinet.id;
    final currentDrugs = List<Drug>.from(activeCabinet.drugs);
    if (currentDrugs.isEmpty || _isSyncing) return;

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final rxcuis = currentDrugs.map((d) => d.rxcui).toList();
      final response = await _apiService.checkUpdates(
        rxcuis: rxcuis,
        lastChecked: _lastChecked,
      );

      final List updatedDrugsJson = response['drugs'] as List? ?? [];
      final checkedAt = response['checked_at'] as String? ?? DateTime.now().toIso8601String();
      _lastNewAlertsCount = response['updates_found'] as int? ?? 0;

      // Update target cabinet items with fresh status
      final updatedCabinetDrugs = <Drug>[];
      for (final existing in currentDrugs) {
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
          updatedCabinetDrugs.add(updated);

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
            final reason = updated.activeShortageDetails.isNotEmpty &&
                    updated.activeShortageDetails[0]['reason'] != null
                ? updated.activeShortageDetails[0]['reason'] as String
                : 'Demand increase or manufacturing delay';
            await _notificationService.showShortageNotification(
              drugName: updated.displayName,
              reason: reason,
            );
          }
        } else {
          updatedCabinetDrugs.add(existing);
        }
      }

      final targetIdx = _cabinets.indexWhere((c) => c.id == targetId);
      if (targetIdx >= 0) {
        _cabinets[targetIdx] = _cabinets[targetIdx].copyWith(drugs: updatedCabinetDrugs);
      }
      _lastChecked = checkedAt;

      await _storageService.saveCabinets(_cabinets);
      await _storageService.saveLastCheckedTimestamp(checkedAt);
    } catch (e) {
      _syncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
}
