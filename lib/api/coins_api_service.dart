import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class CoinsApiService {
  const CoinsApiService();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<int?> fetchBalance({
    required String accessToken,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http.get(
      _uri('/v1/coins/balance'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['coins'] as num?)?.toInt();
  }

  Future<int?> consume({
    required String accessToken,
    required int amount,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http.post(
      _uri('/v1/coins/consume'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'amount': amount}),
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['coins'] as num?)?.toInt();
  }
}

