import 'dart:async' show unawaited;

import 'package:shared_preferences/shared_preferences.dart';
import '../auth/bff_auth_service.dart';
import '../supabase/supabase_config.dart';
import 'games_api_service.dart';

const GamesApiService _gamesApiService = GamesApiService();

Future<bool> syncGameStatsToApiIfAvailable() async {
  if (!SupabaseConfig.isConfigured) return false;
  final token = await BffAuthService.instance.getValidAccessToken();
  if (token == null || token.isEmpty) return false;

  final prefs = await SharedPreferences.getInstance();
  final best = prefs.getDouble('bestRecord');
  final bestSeconds = (best != null && best.isFinite && !best.isNaN) ? best : null;
  final wordGameLevel = prefs.getInt('word_game_level') ?? 1;
  final timingTapBestScore = prefs.getInt('timing_tap_best_score') ?? 0;
  final cigaretteCatchBestStage = prefs.getInt('cigarette_catch_best_stage') ?? 0;
  final cigaretteCatchBestScore = prefs.getInt('cigarette_catch_best_score') ?? 0;

  try {
    return await _gamesApiService.syncStats(
      accessToken: token,
      numberSequenceBestSeconds: bestSeconds,
      wordGameLevel: wordGameLevel,
      timingTapBestScore: timingTapBestScore,
      cigaretteCatchBestStage: cigaretteCatchBestStage,
      cigaretteCatchBestScore: cigaretteCatchBestScore,
    );
  } catch (_) {
    return false;
  }
}

void unawaitedSyncGameStatsToApiIfAvailable() {
  unawaited(syncGameStatsToApiIfAvailable());
}

