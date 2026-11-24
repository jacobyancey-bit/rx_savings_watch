import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/drug.dart';

class ApiService {
  final String _configuredBaseUrl;

  // Common maintenance drug RXCUIs used for k-anonymity query chaffing (differential privacy)
  static const List<String> _chaffRxcuis = [
    '197361', // amlodipine
    '6809',   // metformin
    '11289',  // atorvastatin
    '29046',  // lisinopril
    '6918',   // metoprolol
  ];

  ApiService({String? baseUrl})
      : _configuredBaseUrl = baseUrl ?? defaultBaseUrl;

  static const String productionBaseUrl = 'https://rx.dangling-dice-studios.com';

  static String get defaultBaseUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http://') || origin.startsWith('https://')) {
        return origin;
      }
      return productionBaseUrl;
    }
    return productionBaseUrl;
  }

  String get baseUrl => _configuredBaseUrl;

  /// Check server health
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Search or list available catalog drugs with optional query and pagination.
  /// Uses POST /api/drugs/search when a search query is present so drug names never appear in HTTP URL logs.
  Future<List<Drug>> getDrugs({String? query, int limit = 50, int offset = 0}) async {
    final trimmedQuery = query?.trim() ?? '';
    final http.Response response;

    if (trimmedQuery.isNotEmpty) {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/drugs/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'q': trimmedQuery,
              'limit': limit,
              'offset': offset,
            }),
          )
          .timeout(const Duration(seconds: 18));
    } else {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      final uri = Uri.parse('$baseUrl/api/drugs').replace(queryParameters: queryParams);
      response = await http.get(uri).timeout(const Duration(seconds: 10));
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch drugs catalog: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List list = data['drugs'] as List? ?? [];
    return list.map((json) => Drug.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Anonymous check-updates call with k-anonymity chaffing (differential privacy)
  /// Injects dummy maintenance RXCUIs so network observers cannot infer actual prescriptions,
  /// then strips the dummy items before returning.
  Future<Map<String, dynamic>> checkUpdates({
    required List<String> rxcuis,
    String? lastChecked,
    bool enableChaffing = true,
  }) async {
    if (rxcuis.isEmpty) {
      return {'success': true, 'updates_found': 0, 'drugs': []};
    }

    final originalRxcuiSet = Set<String>.from(rxcuis.map((e) => e.toString()));
    final paddedRxcuis = List<String>.from(rxcuis);

    // Inject chaff if enabled to protect privacy against network snooping
    if (enableChaffing && rxcuis.length < 10) {
      final rand = Random();
      final availableChaff = _chaffRxcuis.where((c) => !originalRxcuiSet.contains(c)).toList();
      availableChaff.shuffle(rand);
      // Add 1 to 2 dummy RXCUIs
      final toAdd = availableChaff.take(min(2, availableChaff.length));
      paddedRxcuis.addAll(toAdd);
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/check-updates'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'rxcuis': paddedRxcuis,
            'last_checked': ?lastChecked,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Failed to check updates: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    // Filter out dummy chaff items so client state only contains user's actual prescriptions
    final List returnedDrugs = data['drugs'] as List? ?? [];
    final filteredDrugs = returnedDrugs
        .where((d) => originalRxcuiSet.contains(d['rxcui']?.toString()))
        .toList();

    return {
      ...data,
      'drugs': filteredDrugs,
      'updates_found': filteredDrugs.fold<int>(0, (sum, d) => sum + ((d['new_alerts_count'] as int?) ?? 0)),
    };
  }

  /// Fetch verified cash & discount pharmacy links, optional PBM discount card, and brand assistance.
  /// Uses POST /api/drugs/partners so RxCUIs never appear in HTTP URL access logs.
  Future<Map<String, dynamic>> getSavingsOptions(String rxcui) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/drugs/partners'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'rxcui': rxcui}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return const {'partners': [], 'discount_card': null, 'brand_assistance': null};
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return const {'partners': [], 'discount_card': null, 'brand_assistance': null};
    }
  }

  /// Zero-PII local sponsored pharmacy lookup (sends ONLY a 5-digit ZIP, never a drug name or RxCUI).
  Future<List<Map<String, dynamic>>> getLocalSponsoredPharmacies(String zip) async {
    final clean = zip.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length != 5) return const [];
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/b2b/local'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'zip': clean}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['partners'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Submit a strictly anonymous, zero-PII data quality flag (enum only, no free text)
  Future<bool> submitDataQualityFlag({
    required String rxcui,
    required String issueType,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/drugs/$rxcui/flag'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'issue_type': issueType}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Submit a private review / feedback directly to support@danglingdicestudios.com
  /// (never displayed publicly to other users).
  Future<({bool ok, String? error})> submitReview({
    required int rating,
    required String category,
    required String message,
  }) async {
    try {
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'unknown');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/reviews'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'rating': rating,
              'category': category,
              'message': message,
              'platform': platform,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 201) {
        return (ok: true, error: null);
      }
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['message'] != null) {
          return (ok: false, error: decoded['message'].toString());
        }
        if (decoded is Map && decoded['error'] != null) {
          return (ok: false, error: decoded['error'].toString());
        }
      } catch (_) {}
      return (ok: false, error: 'Could not send review right now. Please try again.');
    } catch (_) {
      return (ok: false, error: 'Could not reach server. You can also email support@danglingdicestudios.com.');
    }
  }
}
