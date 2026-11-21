import 'pricing_info.dart';
import 'alert_event.dart';

class Drug {
  final String rxcui;
  final String? brandName;
  final String genericName;
  final String? activeIngredient;
  final String? dosageForm;
  final String? strength;
  final String? route;
  final String drugType; // 'small_molecule' or 'biologic'
  
  // Status flags updated via sync
  final bool hasApprovedGeneric;
  final bool commercialGenericAvailable;
  final String substitutionStatus; // 'auto_substitutable', 'doctor_prescription_required', 'brand_only'
  final String? teCode;
  final String? biosimilarStatus;
  final List<String> verificationSources;
  final int genericManufacturersCount;
  final List<String> genericManufacturers;
  final PricingInfo? pricing;
  final bool hasActiveShortage;
  final List<Map<String, dynamic>> activeShortageDetails;
  final List<AlertEvent> alerts;
  final String? lastUpdated;

  Drug({
    required this.rxcui,
    this.brandName,
    required this.genericName,
    this.activeIngredient,
    this.dosageForm,
    this.strength,
    this.route,
    this.drugType = 'small_molecule',
    this.hasApprovedGeneric = false,
    this.commercialGenericAvailable = false,
    this.substitutionStatus = 'brand_only',
    this.teCode,
    this.biosimilarStatus,
    this.verificationSources = const [],
    this.genericManufacturersCount = 0,
    this.genericManufacturers = const [],
    this.pricing,
    this.hasActiveShortage = false,
    this.activeShortageDetails = const [],
    this.alerts = const [],
    this.lastUpdated,
  });

  bool get isAutoSubstitutable => substitutionStatus == 'auto_substitutable';

  String get substitutionPlainGuidance {
    if (!commercialGenericAvailable) {
      return hasApprovedGeneric
          ? 'FDA approved, but not yet widely stocked at pharmacies.'
          : 'Currently available as brand-name only.';
    }
    if (isAutoSubstitutable) {
      if (drugType == 'biologic') {
        return 'FDA Interchangeable — Your pharmacist can usually switch this automatically.';
      }
      final codeLabel = teCode != null ? ' (FDA $teCode-rated)' : '';
      return 'Pharmacist can usually substitute automatically$codeLabel.';
    }
    return 'Requires a new prescription from your doctor to switch.';
  }

  String get displayName => brandName != null && brandName!.isNotEmpty
      ? brandName!
      : genericName;

  /// Distinct official strengths/dosages available for this canonical medication
  List<String> get availableStrengths {
    if (strength == null || strength!.trim().isEmpty) return const [];
    return strength!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String get subtitle {
    final parts = <String>[];
    if (brandName != null && brandName!.isNotEmpty && brandName!.toLowerCase() != genericName.toLowerCase()) {
      parts.add(genericName);
    }
    final strengths = availableStrengths;
    if (strengths.length == 1) {
      parts.add(strengths.first);
    } else if (strengths.length > 1) {
      parts.add('${strengths.length} strengths available');
    }
    if (dosageForm != null && dosageForm!.isNotEmpty) {
      parts.add(dosageForm!);
    }
    return parts.join(' • ');
  }

  factory Drug.fromJson(Map<String, dynamic> json) {
    return Drug(
      rxcui: json['rxcui']?.toString() ?? '',
      brandName: json['brand_name'] as String?,
      genericName: json['generic_name'] as String? ?? 'Unknown Generic',
      activeIngredient: json['active_ingredient'] as String?,
      dosageForm: json['dosage_form'] as String?,
      strength: json['strength'] as String?,
      route: json['route'] as String?,
      drugType: json['drug_type'] as String? ?? 'small_molecule',
      hasApprovedGeneric: json['has_approved_generic'] as bool? ?? false,
      commercialGenericAvailable: json['commercial_generic_available'] as bool? ?? false,
      substitutionStatus: json['substitution_status'] as String? ?? 'brand_only',
      teCode: json['te_code'] as String?,
      biosimilarStatus: json['biosimilar_status'] as String?,
      verificationSources: json['verification_sources'] is List
          ? List<String>.from(json['verification_sources'])
          : const [],
      genericManufacturersCount: json['generic_manufacturers_count'] as int? ?? 0,
      genericManufacturers: json['generic_manufacturers'] is List
          ? List<String>.from(json['generic_manufacturers'])
          : const [],
      pricing: json['pricing'] is Map<String, dynamic>
          ? PricingInfo.fromJson(json['pricing'] as Map<String, dynamic>)
          : null,
      hasActiveShortage: json['has_active_shortage'] as bool? ?? false,
      activeShortageDetails: json['active_shortage_details'] is List
          ? List<Map<String, dynamic>>.from(json['active_shortage_details'])
          : const [],
      alerts: json['alerts'] is List
          ? (json['alerts'] as List)
              .map((a) => AlertEvent.fromJson(a as Map<String, dynamic>))
              .toList()
          : const [],
      lastUpdated: json['last_updated'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rxcui': rxcui,
      'brand_name': brandName,
      'generic_name': genericName,
      'active_ingredient': activeIngredient,
      'dosage_form': dosageForm,
      'strength': strength,
      'route': route,
      'drug_type': drugType,
      'has_approved_generic': hasApprovedGeneric,
      'commercial_generic_available': commercialGenericAvailable,
      'substitution_status': substitutionStatus,
      'te_code': teCode,
      'biosimilar_status': biosimilarStatus,
      'verification_sources': verificationSources,
      'generic_manufacturers_count': genericManufacturersCount,
      'generic_manufacturers': genericManufacturers,
      'pricing': pricing?.toJson(),
      'has_active_shortage': hasActiveShortage,
      'active_shortage_details': activeShortageDetails,
      'alerts': alerts.map((a) => a.toJson()).toList(),
      'last_updated': lastUpdated,
    };
  }

  Drug copyWithUpdate(Map<String, dynamic> updateJson) {
    return Drug(
      rxcui: rxcui,
      brandName: updateJson['brand_name'] as String? ?? brandName,
      genericName: updateJson['generic_name'] as String? ?? genericName,
      activeIngredient: activeIngredient,
      dosageForm: updateJson['dosage_form'] as String? ?? dosageForm,
      strength: updateJson['strength'] as String? ?? strength,
      route: route,
      drugType: updateJson['drug_type'] as String? ?? drugType,
      hasApprovedGeneric: updateJson['has_approved_generic'] as bool? ?? hasApprovedGeneric,
      commercialGenericAvailable: updateJson['commercial_generic_available'] as bool? ?? commercialGenericAvailable,
      substitutionStatus: updateJson['substitution_status'] as String? ?? substitutionStatus,
      teCode: updateJson['te_code'] as String? ?? teCode,
      biosimilarStatus: updateJson['biosimilar_status'] as String? ?? biosimilarStatus,
      verificationSources: updateJson['verification_sources'] is List
          ? List<String>.from(updateJson['verification_sources'])
          : verificationSources,
      genericManufacturersCount: updateJson['generic_manufacturers_count'] as int? ?? genericManufacturersCount,
      genericManufacturers: updateJson['generic_manufacturers'] is List
          ? List<String>.from(updateJson['generic_manufacturers'])
          : genericManufacturers,
      pricing: updateJson['pricing'] is Map<String, dynamic>
          ? PricingInfo.fromJson(updateJson['pricing'] as Map<String, dynamic>)
          : pricing,
      hasActiveShortage: updateJson['has_active_shortage'] as bool? ?? hasActiveShortage,
      activeShortageDetails: updateJson['active_shortage_details'] is List
          ? List<Map<String, dynamic>>.from(updateJson['active_shortage_details'])
          : activeShortageDetails,
      alerts: updateJson['alerts'] is List
          ? (updateJson['alerts'] as List)
              .map((a) => AlertEvent.fromJson(a as Map<String, dynamic>))
              .toList()
          : alerts,
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
}
