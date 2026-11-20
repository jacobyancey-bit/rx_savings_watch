import 'package:flutter/foundation.dart';
import '../models/drug.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class CabinetProvider extends ChangeNotifier {
  final StorageService _storageService;
  late ApiService _apiService;

  List<Drug> _cabinet = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _lastChecked;
  String? _syncError;
  int _lastNewAlertsCount = 0;

  CabinetProvider({
    StorageService? storageService,
    ApiService? apiService,
  })  : _storageService = storageService ?? StorageService(),
        _apiService = apiService ?? ApiService() {
    _init();
  }

  List<Drug> get cabinet => List.unmodifiable(_cabinet);
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get lastChecked => _lastChecked;
  String? get syncError => _syncError;
  int get lastNewAlertsCount => _lastNewAlertsCount;
  String get serverUrl => _apiService.baseUrl;

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

    _cabinet = await _storageService.loadCabinet();
    _lastChecked = await _storageService.getLastCheckedTimestamp();
    _isLoading = false;
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

  Future<void> addDrug(Drug drug) async {
    if (isWatched(drug.rxcui)) return;

    _cabinet.add(drug);
    await _storageService.saveCabinet(_cabinet);
    notifyListeners();

    // Trigger sync for this new drug
    await syncCabinet();
  }

  Future<void> removeDrug(String rxcui) async {
    _cabinet.removeWhere((d) => d.rxcui == rxcui);
    await _storageService.saveCabinet(_cabinet);
    notifyListeners();
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
          updatedCabinet.add(existing.copyWithUpdate(match));
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
