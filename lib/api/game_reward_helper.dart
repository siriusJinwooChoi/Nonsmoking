import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../auth/bff_auth_service.dart';
import '../screens/attendance_screen.dart';
import '../supabase/supabase_config.dart';
import '../supabase/supabase_sync_service.dart';
import 'game_sync_helper.dart';
import 'games_api_service.dart';

const GamesApiService _gamesApi = GamesApiService();

/// 게임 기록을 서버에 반영한 뒤, 서버 검증 일일 보상을 요청합니다.
/// 로그인·API 미설정 시 null.
Future<GameRewardClaimResult?> claimGameDailyRewardIfAvailable({
  required String game,
  Map<String, dynamic>? proof,
}) async {
  if (!SupabaseConfig.isConfigured) return null;
  final token = await BffAuthService.instance.getValidAccessToken();
  if (token == null || token.isEmpty) return null;

  final synced = await syncGameStatsToApiIfAvailable();
  if (!synced) return null;

  try {
    final r = await _gamesApi.claimDailyReward(
      accessToken: token,
      game: game,
      proof: proof,
    );
    if (r != null) {
      await setGoldenCoins(r.coins);
      unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    }
    return r;
  } catch (_) {
    return null;
  }
}

Future<void> syncStatsThenClaimGameRewardWithSnackBar(
  BuildContext context, {
  required String game,
  Map<String, dynamic>? proof,
}) async {
  final r = await claimGameDailyRewardIfAvailable(game: game, proof: proof);
  if (!context.mounted || r == null) return;
  if (r.granted > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('게임 보상! 금연코인 +${r.granted}')),
    );
  }
}
