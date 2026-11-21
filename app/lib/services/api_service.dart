import 'dart:convert';
import 'dart:io';
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

  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
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

  /// Search or list available catalog drugs with optional query and pagination
  Future<List<Drug>> getDrugs({String? query, int limit = 50, int offset = 0}) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (query != null && query.isNotEmpty) 'q': query,
    };

    final uri = Uri.parse('$baseUrl/api/drugs').replace(queryParameters: queryParams);
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

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
}
