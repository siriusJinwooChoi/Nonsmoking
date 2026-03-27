import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class ReasonsApiService {
  const ReasonsApiService();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<String?> fetchPinnedReason({
    required String accessToken,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http.get(
      _uri('/v1/reasons'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) return null;
    final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
    final text = body['pinnedReasonText'] as String?;
    final trimmed = text?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

  Future<bool> savePinnedReason({
    required String accessToken,
    required String text,
  }) async {
    if (!ApiConfig.isConfigured) return false;
    final res = await http.put(
      _uri('/v1/reasons/pinned'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'text': text}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}

