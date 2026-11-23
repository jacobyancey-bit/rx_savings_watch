import 'dart:convert';
import 'pricing_info.dart';
import 'alert_event.dart';

class DosageFormOption {
  final String form;
  final List<String> strengths;

  const DosageFormOption({
    required this.form,
    required this.strengths,
  });

  factory DosageFormOption.fromJson(Map<String, dynamic> json) {
    return DosageFormOption(
      form: (json['form'] ?? 'Oral').toString(),
      strengths: json['strengths'] is List
          ? List<String>.from((json['strengths'] as List).map((e) => e.toString()))
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'form': form,
        'strengths': strengths,
      };
}

class Drug {
  final String rxcui;
  final String? brandName;
  final String genericName;
  final String? activeIngredient;
  final String? dosageForm;
  final String? strength;
  final List<DosageFormOption> dosageOptions;
  final List<String> referenceBrands;
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
    this.dosageOptions = const [],
    this.referenceBrands = const [],
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

  /// True when the user is viewing an unbranded generic entry directly (e.g. propranolol, tamsulosin)
  /// rather than a branded medication (e.g. Flomax, Lipitor).
  bool get isUnbrandedGeneric =>
      brandName == null ||
      brandName!.trim().isEmpty ||
      brandName!.trim().toLowerCase() == genericName.trim().toLowerCase();

  String get substitutionPlainGuidance {
    if (isUnbrandedGeneric) {
      if (referenceBrands.isNotEmpty) {
        return 'You are already viewing the generic version of ${referenceBrands.join(', ')}.';
      }
      return 'You are already viewing the FDA-approved generic medication.';
    }
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

  /// Groups available strengths cleanly by exact FDA Dosage Form when provided by the server
  /// (e.g. Oral Tablet, Extended-Release Capsule, Oral Solution, Injectable), falling back to
  /// unit/form classification for legacy cached records.
  Map<String, List<String>> get groupedStrengthsByRoute {
    if (dosageOptions.isNotEmpty) {
      final exact = <String, List<String>>{};
      for (final opt in dosageOptions) {
        if (opt.strengths.isNotEmpty) {
          exact[opt.form] = opt.strengths;
        }
      }
      if (exact.isNotEmpty) return exact;
    }

    final strengths = availableStrengths;
    if (strengths.isEmpty) return const {};

    final formLower = '${dosageForm ?? ''} ${route ?? ''}'.toLowerCase();
    final isTopicalForm = RegExp(r'cream|oint|gel|lotion|patch|topical|transdermal|foam|shampoo').hasMatch(formLower);
    final isInhalerForm = RegExp(r'inhal|aerosol|nebul|spray|diskus|ellipta').hasMatch(formLower);
    final isEyeEarForm = RegExp(r'ophthalm|optic|eye|otic|ear').hasMatch(formLower);
    final isInjectableForm = RegExp(r'inject|intraven|infus|syringe|vial|ampul|subcut|intramusc|auto-injector').hasMatch(formLower);

    final grouped = <String, List<String>>{};
    for (final s in strengths) {
      final lower = s.toLowerCase();
      String bucket;

      if (lower.contains('actuat') || lower.contains('inh') || isInhalerForm) {
        bucket = 'Inhaler / Spray';
      } else if (isEyeEarForm) {
        bucket = 'Eye / Ear Drops';
      } else if (lower.contains('%') ||
          RegExp(r'/\s*\d*(?:\.\d+)?\s*(?:g|gm)\b').hasMatch(lower) ||
          lower.contains('24hr') ||
          isTopicalForm) {
        bucket = 'Topical';
      } else if (RegExp(r'/\s*\d*(?:\.\d+)?\s*ml\b').hasMatch(lower) ||
          RegExp(r'^\d+(?:\.\d+)?\s*ml$').hasMatch(lower)) {
        bucket = isInjectableForm ? 'Injectable / Liquid' : 'Liquid / Injectable';
      } else if (isInjectableForm && drugType == 'biologic') {
        bucket = 'Injectable';
      } else {
        bucket = 'Oral (Pill / Capsule)';
      }

      grouped.putIfAbsent(bucket, () => <String>[]).add(s);
    }

    // Order buckets so Oral appears first when present (most common patient route)
    const preferredOrder = [
      'Oral (Pill / Capsule)',
      'Injectable / Liquid',
      'Liquid / Injectable',
      'Injectable',
      'Inhaler / Spray',
      'Topical',
      'Eye / Ear Drops',
    ];
    final ordered = <String, List<String>>{};
    for (final key in preferredOrder) {
      if (grouped.containsKey(key)) {
        ordered[key] = grouped[key]!;
      }
    }
    for (final entry in grouped.entries) {
      ordered.putIfAbsent(entry.key, () => entry.value);
    }
    return ordered;
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

  static List<DosageFormOption> _parseDosageOptions(dynamic raw) {
    if (raw == null) return const [];
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DosageFormOption.fromJson)
          .where((o) => o.strengths.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static List<String> _parseReferenceBrands(dynamic raw) {
    if (raw == null) return const [];
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is List) {
      return decoded
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  factory Drug.fromJson(Map<String, dynamic> json) {
    return Drug(
      rxcui: json['rxcui']?.toString() ?? '',
      brandName: json['brand_name'] as String?,
      genericName: json['generic_name'] as String? ?? 'Unknown Generic',
      activeIngredient: json['active_ingredient'] as String?,
      dosageForm: json['dosage_form'] as String?,
      strength: json['strength'] as String?,
      dosageOptions: _parseDosageOptions(json['dosage_options']),
      referenceBrands: _parseReferenceBrands(json['reference_brands']),
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
      'dosage_options': dosageOptions.map((o) => o.toJson()).toList(),
      'reference_brands': referenceBrands,
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
      dosageOptions: updateJson['dosage_options'] != null
          ? _parseDosageOptions(updateJson['dosage_options'])
          : dosageOptions,
      referenceBrands: updateJson['reference_brands'] != null
          ? _parseReferenceBrands(updateJson['reference_brands'])
          : referenceBrands,
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
