import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class GameRewardClaimResult {
  final int coins;
  final int granted;
  final bool alreadyClaimed;

  const GameRewardClaimResult({
    required this.coins,
    required this.granted,
    required this.alreadyClaimed,
  });
}

/// `GET /v1/games/reward/settings` 응답 (Render 등 서버 환경변수 반영)
class GameRewardSettings {
  final int rewardCoinsPerClaim;
  final int statsFreshMinutes;
  final int wordGameMinLevelForReward;
  final int timingTapMinBestScoreForReward;
  final int cigaretteCatchMinBestScoreForReward;

  const GameRewardSettings({
    required this.rewardCoinsPerClaim,
    required this.statsFreshMinutes,
    required this.wordGameMinLevelForReward,
    required this.timingTapMinBestScoreForReward,
    required this.cigaretteCatchMinBestScoreForReward,
  });

  factory GameRewardSettings.fromJson(Map<String, dynamic> j) {
    return GameRewardSettings(
      rewardCoinsPerClaim: (j['rewardCoinsPerClaim'] as num?)?.toInt() ?? 2,
      statsFreshMinutes: (j['statsFreshMinutes'] as num?)?.toInt() ?? 25,
      wordGameMinLevelForReward: (j['wordGameMinLevelForReward'] as num?)?.toInt() ?? 2,
      timingTapMinBestScoreForReward: (j['timingTapMinBestScoreForReward'] as num?)?.toInt() ?? 1,
      cigaretteCatchMinBestScoreForReward:
          (j['cigaretteCatchMinBestScoreForReward'] as num?)?.toInt() ?? 1,
    );
  }
}

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

  /// 서버 검증 일일 게임 보상 (종목당 1일 1회)
  Future<GameRewardClaimResult?> claimDailyReward({
    required String accessToken,
    required String game,
    Map<String, dynamic>? proof,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http.post(
      _uri('/v1/games/reward/claim'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'game': game,
        if (proof != null && proof.isNotEmpty) 'proof': proof,
      }),
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final coins = (body['coins'] as num?)?.toInt();
    final granted = (body['granted'] as num?)?.toInt() ?? 0;
    if (coins == null) return null;
    return GameRewardClaimResult(
      coins: coins,
      granted: granted,
      alreadyClaimed: body['alreadyClaimed'] == true,
    );
  }

  Future<GameRewardSettings?> fetchRewardSettings({
    required String accessToken,
  }) async {
    if (!ApiConfig.isConfigured) return null;
    final res = await http.get(
      _uri('/v1/games/reward/settings'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['ok'] != true) return null;
    return GameRewardSettings.fromJson(body);
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

