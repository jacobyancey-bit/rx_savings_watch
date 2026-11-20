import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/drug.dart';

class ApiService {
  final String _configuredBaseUrl;

  ApiService({String? baseUrl})
      : _configuredBaseUrl = baseUrl ?? defaultBaseUrl;

  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (Platform.isAndroid) {
      // 10.0.2.2 maps to host localhost from standard Android emulator
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

  /// Search or list available catalog drugs
  Future<List<Drug>> getDrugs() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/drugs'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch drugs catalog: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final List list = data['drugs'] as List? ?? [];
    return list.map((json) => Drug.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Anonymous check-updates call
  /// Sends ONLY rxcuis and last_checked. No user ID or PII is sent.
  Future<Map<String, dynamic>> checkUpdates({
    required List<String> rxcuis,
    String? lastChecked,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/check-updates'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'rxcuis': rxcuis,
            'last_checked': ?lastChecked,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Failed to check updates: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
