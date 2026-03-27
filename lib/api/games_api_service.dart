import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class GamesApiService {
  const GamesApiService();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  Future<bool> syncStats({
    required String accessToken,
    double? numberSequenceBestSeconds,
    required int wordGameLevel,
    required int timingTapBestScore,
    required int cigaretteCatchBestStage,
    required int cigaretteCatchBestScore,
  }) async {
    if (!ApiConfig.isConfigured) return false;
    final res = await http.put(
      _uri('/v1/games/stats'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'numberSequenceBestSeconds': numberSequenceBestSeconds,
        'wordGameLevel': wordGameLevel,
        'timingTapBestScore': timingTapBestScore,
        'cigaretteCatchBestStage': cigaretteCatchBestStage,
        'cigaretteCatchBestScore': cigaretteCatchBestScore,
      }),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<Map<String, dynamic>?> fetchRankings({
    required String accessToken,
    int limit = 10,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final uri = _uri('/v1/games/rankings?limit=$limit');
    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

