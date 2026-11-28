import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zero-PHI RevenueCat subscription manager for Rx Savings Watch (Android & iOS).
///
/// - Uses anonymous RevenueCat App User IDs (no login, email, or personal info).
/// - Checks the `caregiver_plus` entitlement for Monthly (`monthly`) & Yearly (`yearly`) plans.
/// - Safely no-ops on Web (PWA) and in headless widget tests.
class SubscriptionService extends ChangeNotifier {
  static const String caregiverPlusEntitlementId = 'caregiver_plus';
  static const String monthlyProductId = 'monthly';
  static const String yearlyProductId = 'yearly';
  static const String _cachedPlusKey = 'rc_caregiver_plus_cached';

  /// Override at build time with `--dart-define=REVENUECAT_ANDROID_KEY=...` if needed.
  static const String _androidApiKeyOverride = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: '',
  );
  static const String _androidReleaseKey = 'goog_OCQcwVTKkzbaLisHHIbExdeMKjZ';
  static const String _testStoreKey = 'test_ERaefrnlGGnFGPudnyYzJDeGbvu';

  static const String _iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: _testStoreKey,
  );

  bool _isConfigured = false;
  bool _isCaregiverPlus = false;
  bool _isBusy = false;
  String? _lastError;
  CustomerInfo? _customerInfo;
  SharedPreferences? _prefs;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get isConfigured => _isConfigured;
  bool get isCaregiverPlus => _isCaregiverPlus;
  bool get isBusy => _isBusy;
  String? get lastError => _lastError;
  CustomerInfo? get customerInfo => _customerInfo;

  String get _platformApiKey {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _iosApiKey;
    if (_androidApiKeyOverride.isNotEmpty) return _androidApiKeyOverride;
    return kDebugMode ? _testStoreKey : _androidReleaseKey;
  }

  Future<void> init() async {
    if (!isSupported) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _isCaregiverPlus = _prefs?.getBool(_cachedPlusKey) ?? false;
      notifyListeners();
    } catch (_) {}

    await ensureConfigured();
  }

  Future<bool> ensureConfigured() async {
    if (!isSupported) return false;
    if (_isConfigured) return true;

    final apiKey = _platformApiKey.trim();
    if (apiKey.isEmpty) return false;

    if (!kDebugMode && apiKey.startsWith('test_')) {
      debugPrint(
        '[RevenueCat] Warning: Using a test API key in release mode. '
        'Pass --dart-define=REVENUECAT_ANDROID_KEY=goog_... for production.',
      );
    }

    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      final config = PurchasesConfiguration(apiKey);
      await Purchases.configure(config);
      _isConfigured = true;

      Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
      return true;
    } catch (e) {
      debugPrint('[RevenueCat] Initialization skipped/failed: $e');
      return false;
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    _customerInfo = info;
    final active =
        info.entitlements.all[caregiverPlusEntitlementId]?.isActive == true;
    final changed = active != _isCaregiverPlus;
    _isCaregiverPlus = active;
    _prefs?.setBool(_cachedPlusKey, active);
    if (changed) {
      notifyListeners();
    }
  }

  /// Fetch current Offering packages (e.g. Monthly `monthly` and Yearly `yearly`).
  Future<List<Package>> getAvailablePackages() async {
    if (!await ensureConfigured()) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? const [];
    } catch (e) {
      debugPrint('[RevenueCat] Failed to fetch offerings: $e');
      return const [];
    }
  }

  /// Present the RevenueCat Paywall only if the user does not already have `caregiver_plus`.
  Future<({bool active, String? message})> presentPaywall() async {
    if (!isSupported) {
      return (active: false, message: 'Subscriptions are available in the mobile app.');
    }
    if (_isBusy) return (active: _isCaregiverPlus, message: null);

    _isBusy = true;
    _lastError = null;
    notifyListeners();

    try {
      if (!await ensureConfigured()) {
        return (active: false, message: 'Subscriptions are unavailable right now.');
      }

      final result = await RevenueCatUI.presentPaywallIfNeeded(
        caregiverPlusEntitlementId,
        displayCloseButton: true,
      );

      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);

      return switch (result) {
        PaywallResult.purchased => (
            active: _isCaregiverPlus,
            message: 'Welcome to Rx Savings Watch Plus!',
          ),
        PaywallResult.restored => (
            active: _isCaregiverPlus,
            message: 'Your Caregiver Plus subscription has been restored.',
          ),
        PaywallResult.notPresented => (
            active: _isCaregiverPlus,
            message: _isCaregiverPlus ? 'Caregiver Plus is already active.' : null,
          ),
        PaywallResult.cancelled => (active: _isCaregiverPlus, message: null),
        PaywallResult.error => (
            active: _isCaregiverPlus,
            message: 'Could not complete purchase. Please try again.',
          ),
      };
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return (active: _isCaregiverPlus, message: null);
      }
      _lastError = e.message ?? 'Subscription error occurred.';
      return (active: _isCaregiverPlus, message: _lastError);
    } catch (e) {
      _lastError = 'Could not open subscription options. Please try again.';
      debugPrint('[RevenueCat] Paywall error: $e');
      return (active: _isCaregiverPlus, message: _lastError);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Present RevenueCat Customer Center so subscribers can manage, cancel, or get support.
  Future<String?> presentCustomerCenter() async {
    if (!isSupported) return 'Manage subscriptions from the mobile app.';
    if (!await ensureConfigured()) {
      return 'Subscription management is unavailable right now.';
    }
    try {
      await RevenueCatUI.presentCustomerCenter();
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
      return null;
    } catch (e) {
      debugPrint('[RevenueCat] Customer Center error: $e');
      return 'Could not open subscription management right now.';
    }
  }

  /// Restore prior Google Play / App Store purchases.
  Future<({bool active, String message})> restorePurchases() async {
    if (!isSupported) {
      return (active: false, message: 'Restore is available in the mobile app.');
    }
    if (_isBusy) {
      return (active: _isCaregiverPlus, message: 'Please wait...');
    }

    _isBusy = true;
    _lastError = null;
    notifyListeners();

    try {
      if (!await ensureConfigured()) {
        return (active: false, message: 'Store connection unavailable right now.');
      }
      final info = await Purchases.restorePurchases();
      _applyCustomerInfo(info);
      return (
        active: _isCaregiverPlus,
        message: _isCaregiverPlus
            ? 'Caregiver Plus subscription restored!'
            : 'No active Caregiver Plus subscription found for this store account.',
      );
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Could not restore purchases.';
      return (active: _isCaregiverPlus, message: _lastError!);
    } catch (e) {
      debugPrint('[RevenueCat] Restore error: $e');
      return (active: _isCaregiverPlus, message: 'Could not restore purchases right now.');
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
