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
      // 코인 저장/원격 push를 기다리지 않고 즉시 반환해 UI 반응 지연을 줄입니다.
      unawaited(setGoldenCoins(r.coins));
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
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    const SnackBar(
      duration: Duration(seconds: 20),
      content: Text('보상 확인 중...'),
    ),
  );

  final r = await claimGameDailyRewardIfAvailable(game: game, proof: proof);
  if (!context.mounted) return;
  messenger.hideCurrentSnackBar();

  if (r == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('보상 확인이 지연되고 있어요. 잠시 후 다시 확인해 주세요.'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  if (r.granted > 0) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('보상 확정! 금연코인 +${r.granted} (보유 ${r.coins})'),
        duration: const Duration(seconds: 2),
      ),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text('오늘은 이미 수령했어요. 현재 보유 코인 ${r.coins}'),
      duration: const Duration(seconds: 2),
    ),
  );
}
