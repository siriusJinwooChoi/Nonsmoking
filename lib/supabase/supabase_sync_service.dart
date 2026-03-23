import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/daily_reminder_worker.dart' as dw;
import '../screens/attendance_screen.dart' as att;
import 'supabase_config.dart';

/// SharedPreferences 키(앱 코드와 동일한 문자열).
abstract final class _PrefsKeys {
  static const isConfigured = 'isConfigured';
  static const dailyCigarettes = 'dailyCigarettes';
  static const cigarettesPerPack = 'cigarettesPerPack';
  static const pricePerPack = 'pricePerPack';
  static const durationDays = 'duration_days';
  static const startTime = 'startTime';
  static const failureCount = 'failureCount';
  static const lungHealth = 'lungHealth';
  static const lastUpdatedTime = 'lastUpdatedTime';
  static const pinnedReasonText = 'pinnedReasonText';
  static const quitReasonsV1 = 'quitReasons_v1';
  static const selectedReasonId = 'selectedReasonId';
  static const lastCollectionWindow = 'last_collection_window';
  static const sessionWindow = 'cigarette_collect_session_window';
  static const sessionAsset = 'cigarette_collect_session_asset';
  static const sessionAttempts = 'cigarette_collect_session_attempts';
  static const collectedCigaretteAssets = 'collected_cigarette_assets';
  static const growthStage = 'growthStage';
  static const water = 'water';
  static const currentWater = 'currentWater';
  static const lastWaterUpdateTime = 'lastWaterUpdateTime';
  static const savedTreesCount = 'savedTreesCount';
  static const bestRecord = 'bestRecord';
  static const wordGameLevel = 'word_game_level';
  static const timingTapBestScore = 'timing_tap_best_score';
  static const cigaretteCatchBestStage = 'cigarette_catch_best_stage';
  /// 로그아웃 후 다음 로그인 시 원격에서 복원(pull) 필요
  static const pullPendingAfterLogin = 'supabase_pull_pending_after_login';
}

String _initialPullDoneKey(String uid) => 'supabase_initial_pull_done_$uid';

/// 로컬(SharedPreferences)과 Supabase 테이블 간 동기화.
///
/// - **일상 사용**: 로컬이 기준. 앱 시작·백그라운드 등에서는 **push만** (원격을 당겨오지 않음).
/// - **pull**: 로그아웃 후 재로그인, 또는 이 기기에서 해당 계정으로 **처음 세션을 맞출 때만**
///   ([runPostLoginPullIfNeeded]).
///
/// 로그인된 사용자(`auth.currentSession`)만 동기화합니다. (익명 로그인 미사용)
///
/// **가입 시 DB 트리거**로 `user_settings` 등에 기본 행이 생기므로, “원격에 행이 있다”만으로는
/// pull 하지 않습니다. **`user_settings.is_configured`** 가 true일 때만 원격 온보딩 완료로 보고 pull 합니다.
abstract final class SupabaseSyncService {
  static Future<void>? _postLoginPullInFlight;

  /// 로그아웃 직전에 호출: 다음 로그인 시 [runPostLoginPullIfNeeded]에서 pull 하도록 표시.
  static Future<void> markPullRequiredOnNextLogin() async {
    if (!SupabaseConfig.isConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, true);
  }

  /// 앱 시작 시: **로컬 → 서버 push만** (pull 없음).
  static Future<void> runStartupPushOnlyIfEligible() async {
    if (!SupabaseConfig.isConfigured) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_PrefsKeys.isConfigured) ?? false)) return;

    try {
      await _pushAll(prefs);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SupabaseSyncService.runStartupPushOnlyIfEligible: $e\n$st');
      }
    }
  }

  /// 로그인 직후(`signedIn` / `initialSession`): pull 이 필요한 경우에만 원격 반영.
  ///
  /// - 이 기기에서 해당 계정의 **최초 동기화**가 아직이거나
  /// - [markPullRequiredOnNextLogin] 이 설정된 경우(로그아웃 후 재로그인 등)
  static Future<void> runPostLoginPullIfNeeded() async {
    final existing = _postLoginPullInFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final done = _runPostLoginPullIfNeededBody();
    _postLoginPullInFlight = done;
    try {
      await done;
    } finally {
      _postLoginPullInFlight = null;
    }
  }

  static Future<void> _runPostLoginPullIfNeededBody() async {
    if (!SupabaseConfig.isConfigured) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    final prefs = await SharedPreferences.getInstance();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final pending = prefs.getBool(_PrefsKeys.pullPendingAfterLogin) ?? false;
    final initialDone = prefs.getBool(_initialPullDoneKey(uid)) ?? false;
    if (!pending && initialDone) return;

    try {
      final remoteOnboardingDone = await _remoteOnboardingCompleted();
      if (remoteOnboardingDone) {
        await _pullAll(prefs);
      } else if (prefs.getBool(_PrefsKeys.isConfigured) ?? false) {
        await _pushAll(prefs);
      }
      await prefs.setBool(_initialPullDoneKey(uid), true);
      await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SupabaseSyncService.runPostLoginPullIfNeeded: $e\n$st');
      }
    }
  }

  /// 온보딩 완료 직후, 앱 백그라운드 진입 시 등: 로컬 → 서버 업로드.
  static Future<void> pushLocalToRemoteIfEligible() async {
    if (!SupabaseConfig.isConfigured) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_PrefsKeys.isConfigured) ?? false)) return;
      await _pushAll(prefs);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SupabaseSyncService.pushLocalToRemoteIfEligible: $e\n$st');
      }
    }
  }

  /// DB 트리거로 `user_settings` 행은 가입 직후 생기지만 `is_configured` 는 false 가 기본값.
  static Future<bool> _remoteOnboardingCompleted() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await Supabase.instance.client
        .from('user_settings')
        .select('is_configured')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return false;
    return row['is_configured'] as bool? ?? false;
  }

  /// 한 테이블 upsert 실패 시 전체가 중단되면 코인 등 뒤쪽 테이블이 영원히 안 올라갈 수 있어 분리 처리.
  static Future<void> _pushAll(SharedPreferences prefs) async {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final client = Supabase.instance.client;

    Future<void> run(String label, Future<void> Function() op) async {
      try {
        await op();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('SupabaseSyncService._pushAll[$label]: $e\n$st');
        }
      }
    }

    await run('user_settings', () => _upsertUserSettings(client, uid, prefs));
    await run('quit_progress', () => _upsertQuitProgress(client, uid, prefs));
    await run('reasons', () => _upsertReasons(client, uid, prefs));
    await run('notification_settings', () => _upsertNotificationSettings(client, uid, prefs));
    await run('coins_and_attendance', () => _upsertCoinsAndAttendance(client, uid, prefs));
    await run('tree_progress', () => _upsertTreeProgress(client, uid, prefs));
    await run('cigarette_collection', () => _upsertCigaretteCollection(client, uid, prefs));
    await run('game_stats', () => _upsertGameStats(client, uid, prefs));
  }

  static Future<void> _pullAll(SharedPreferences prefs) async {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final client = Supabase.instance.client;

    await _applyUserSettings(
      await client.from('user_settings').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyQuitProgress(
      await client.from('quit_progress').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyReasons(
      await client.from('reasons').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyNotificationSettings(
      await client.from('notification_settings').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyCoinsAndAttendance(
      await client.from('coins_and_attendance').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyTreeProgress(
      await client.from('tree_progress').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyCigaretteCollection(
      await client.from('cigarette_collection').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
    await _applyGameStats(
      await client.from('game_stats').select().eq('user_id', uid).maybeSingle(),
      prefs,
    );
  }

  // --- upsert helpers ---

  static Future<void> _upsertUserSettings(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    await client.from('user_settings').upsert({
      'user_id': uid,
      'is_configured': prefs.getBool(_PrefsKeys.isConfigured) ?? false,
      'daily_cigarettes': prefs.getInt(_PrefsKeys.dailyCigarettes) ?? 0,
      'cigarettes_per_pack': prefs.getInt(_PrefsKeys.cigarettesPerPack) ?? 20,
      'price_per_pack': prefs.getInt(_PrefsKeys.pricePerPack) ?? 4500,
      'duration_days': prefs.getInt(_PrefsKeys.durationDays),
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertQuitProgress(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    final startMs = prefs.getInt(_PrefsKeys.startTime) ??
        DateTime.now().millisecondsSinceEpoch;
    final lungLast =
        prefs.getInt(_PrefsKeys.lastUpdatedTime) ?? startMs;

    await client.from('quit_progress').upsert({
      'user_id': uid,
      'start_time_ms': startMs,
      'failure_count': prefs.getInt(_PrefsKeys.failureCount) ?? 0,
      'goal_days': prefs.getInt(dw.kGoalDaysKey),
      'goal_congratulated_day': prefs.getInt(dw.kGoalCongratulatedDayKey),
      'lung_health': (prefs.getInt(_PrefsKeys.lungHealth) ?? 100).clamp(0, 100),
      'lung_last_updated_ms': lungLast,
      'pinned_reason_text': prefs.getString(_PrefsKeys.pinnedReasonText),
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertReasons(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_PrefsKeys.quitReasonsV1);
    dynamic decoded;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {}
    }
    final list = decoded is List ? decoded : <dynamic>[];

    await client.from('reasons').upsert({
      'user_id': uid,
      'reasons_json': list,
      'selected_reason_id': prefs.getString(_PrefsKeys.selectedReasonId),
      'selected_reason_text': prefs.getString(dw.kSelectedReasonTextKey),
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertNotificationSettings(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    dynamic reminderDecoded;
    final reminderRaw = prefs.getString(dw.kReminderTimesKey);
    if (reminderRaw != null && reminderRaw.trim().isNotEmpty) {
      try {
        reminderDecoded = jsonDecode(reminderRaw);
      } catch (_) {}
    }
    final reminderJson = reminderDecoded is List ? reminderDecoded : <dynamic>[];

    await client.from('notification_settings').upsert({
      'user_id': uid,
      'reminder_times_json': reminderJson,
      'reason_notification_enabled':
          prefs.getBool(dw.kReasonNotificationEnabledKey) ?? false,
      'inactivity_notification_enabled':
          prefs.getBool(dw.kInactivityNotificationEnabledKey) ?? true,
      'attendance_reminder_enabled':
          prefs.getBool(dw.kAttendanceReminderEnabledKey) ?? true,
      'last_app_open_time_ms': prefs.getInt(dw.kLastAppOpenTimeMsKey),
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertCoinsAndAttendance(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    final lastDateStr = prefs.getString(att.kAttendanceLastDateKey);
    String? dateForDb;
    if (lastDateStr != null && lastDateStr.length >= 10) {
      dateForDb = lastDateStr.substring(0, 10);
    } else if (lastDateStr != null && lastDateStr.isNotEmpty) {
      dateForDb = lastDateStr;
    }

    await client.from('coins_and_attendance').upsert({
      'user_id': uid,
      'golden_coins': prefs.getInt(att.kGoldenCoinsKey) ?? 0,
      'attendance_streak_day': prefs.getInt(att.kAttendanceStreakDayKey) ?? 1,
      'attendance_last_date': dateForDb,
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertTreeProgress(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    final lastMs = prefs.getInt(_PrefsKeys.lastWaterUpdateTime) ??
        DateTime.now().millisecondsSinceEpoch;

    await client.from('tree_progress').upsert({
      'user_id': uid,
      'growth_stage': prefs.getInt(_PrefsKeys.growthStage) ?? 1,
      'water': prefs.getInt(_PrefsKeys.water) ?? 0,
      'current_water': prefs.getInt(_PrefsKeys.currentWater) ?? 0,
      'last_water_update_ms': lastMs,
      'saved_trees_count': prefs.getInt(_PrefsKeys.savedTreesCount) ?? 0,
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertCigaretteCollection(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    final collected = prefs.getStringList(_PrefsKeys.collectedCigaretteAssets) ?? [];

    await client.from('cigarette_collection').upsert({
      'user_id': uid,
      'last_collection_window': prefs.getString(_PrefsKeys.lastCollectionWindow),
      'session_window': prefs.getString(_PrefsKeys.sessionWindow),
      'session_asset': prefs.getString(_PrefsKeys.sessionAsset),
      'session_attempts': prefs.getInt(_PrefsKeys.sessionAttempts) ?? 0,
      'collected_asset_paths': collected,
    }, onConflict: 'user_id');
  }

  static Future<void> _upsertGameStats(
    SupabaseClient client,
    String uid,
    SharedPreferences prefs,
  ) async {
    final best = prefs.getDouble(_PrefsKeys.bestRecord);
    double? bestSec;
    if (best != null && best.isFinite && !best.isNaN) {
      bestSec = best;
    }

    await client.from('game_stats').upsert({
      'user_id': uid,
      'number_sequence_best_seconds': bestSec,
      'word_game_level': prefs.getInt(_PrefsKeys.wordGameLevel) ?? 1,
      'timing_tap_best_score': prefs.getInt(_PrefsKeys.timingTapBestScore) ?? 0,
      'cigarette_catch_best_stage':
          prefs.getInt(_PrefsKeys.cigaretteCatchBestStage) ?? 0,
    }, onConflict: 'user_id');
  }

  // --- apply (pull) helpers ---

  static Future<void> _applyUserSettings(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    await prefs.setBool(
      _PrefsKeys.isConfigured,
      row['is_configured'] as bool? ?? false,
    );
    await prefs.setInt(
      _PrefsKeys.dailyCigarettes,
      (row['daily_cigarettes'] as num?)?.toInt() ?? 0,
    );
    await prefs.setInt(
      _PrefsKeys.cigarettesPerPack,
      (row['cigarettes_per_pack'] as num?)?.toInt() ?? 20,
    );
    await prefs.setInt(
      _PrefsKeys.pricePerPack,
      (row['price_per_pack'] as num?)?.toInt() ?? 4500,
    );
    final d = row['duration_days'];
    if (d != null) {
      await prefs.setInt(_PrefsKeys.durationDays, (d as num).toInt());
    } else {
      await prefs.remove(_PrefsKeys.durationDays);
    }
  }

  static Future<void> _applyQuitProgress(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    await prefs.setInt(
      _PrefsKeys.startTime,
      (row['start_time_ms'] as num).toInt(),
    );
    await prefs.setInt(
      _PrefsKeys.failureCount,
      (row['failure_count'] as num?)?.toInt() ?? 0,
    );
    final gd = row['goal_days'];
    if (gd != null) {
      await prefs.setInt(dw.kGoalDaysKey, (gd as num).toInt());
    } else {
      await prefs.remove(dw.kGoalDaysKey);
    }
    final gc = row['goal_congratulated_day'];
    if (gc != null) {
      await prefs.setInt(dw.kGoalCongratulatedDayKey, (gc as num).toInt());
    } else {
      await prefs.remove(dw.kGoalCongratulatedDayKey);
    }
    await prefs.setInt(
      _PrefsKeys.lungHealth,
      (row['lung_health'] as num?)?.toInt() ?? 100,
    );
    await prefs.setInt(
      _PrefsKeys.lastUpdatedTime,
      (row['lung_last_updated_ms'] as num).toInt(),
    );
    final pinned = row['pinned_reason_text'] as String?;
    if (pinned != null && pinned.isNotEmpty) {
      await prefs.setString(_PrefsKeys.pinnedReasonText, pinned);
    } else {
      await prefs.remove(_PrefsKeys.pinnedReasonText);
    }
  }

  static Future<void> _applyReasons(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    final j = row['reasons_json'];
    if (j != null) {
      await prefs.setString(_PrefsKeys.quitReasonsV1, jsonEncode(j));
    }
    final sid = row['selected_reason_id'] as String?;
    if (sid != null && sid.isNotEmpty) {
      await prefs.setString(_PrefsKeys.selectedReasonId, sid);
    } else {
      await prefs.remove(_PrefsKeys.selectedReasonId);
    }
    final srt = row['selected_reason_text'] as String?;
    if (srt != null && srt.isNotEmpty) {
      await prefs.setString(dw.kSelectedReasonTextKey, srt);
    } else {
      await prefs.remove(dw.kSelectedReasonTextKey);
    }
  }

  static Future<void> _applyNotificationSettings(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    final j = row['reminder_times_json'];
    if (j != null) {
      await prefs.setString(dw.kReminderTimesKey, jsonEncode(j));
    }
    await prefs.setBool(
      dw.kReasonNotificationEnabledKey,
      row['reason_notification_enabled'] as bool? ?? false,
    );
    await prefs.setBool(
      dw.kInactivityNotificationEnabledKey,
      row['inactivity_notification_enabled'] as bool? ?? true,
    );
    await prefs.setBool(
      dw.kAttendanceReminderEnabledKey,
      row['attendance_reminder_enabled'] as bool? ?? true,
    );
    final lastMs = row['last_app_open_time_ms'];
    if (lastMs != null) {
      await prefs.setInt(dw.kLastAppOpenTimeMsKey, (lastMs as num).toInt());
    } else {
      await prefs.remove(dw.kLastAppOpenTimeMsKey);
    }
  }

  static Future<void> _applyCoinsAndAttendance(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    final remoteCoins = (row['golden_coins'] as num?)?.toInt() ?? 0;
    final d = row['attendance_last_date'];
    final hasRemoteAttendanceDate =
        d != null && d.toString().trim().isNotEmpty;

    // 가입 직후 DB 기본 행 등으로 attendance_last_date 가 비어 있으면,
    // 로컬에서 이미 출석 처리했는데 pull 이 지우는 일을 막는다.
    if (!hasRemoteAttendanceDate) {
      final localCoins = prefs.getInt(att.kGoldenCoinsKey) ?? 0;
      final merged = remoteCoins > localCoins ? remoteCoins : localCoins;
      await prefs.setInt(att.kGoldenCoinsKey, merged);
      return;
    }

    await prefs.setInt(att.kGoldenCoinsKey, remoteCoins);
    await prefs.setInt(
      att.kAttendanceStreakDayKey,
      (row['attendance_streak_day'] as num?)?.toInt() ?? 1,
    );
    final s = d.toString();
    await prefs.setString(
      att.kAttendanceLastDateKey,
      s.length >= 10 ? s.substring(0, 10) : s,
    );
  }

  static Future<void> _applyTreeProgress(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    await prefs.setInt(
      _PrefsKeys.growthStage,
      (row['growth_stage'] as num?)?.toInt() ?? 1,
    );
    await prefs.setInt(
      _PrefsKeys.water,
      (row['water'] as num?)?.toInt() ?? 0,
    );
    await prefs.setInt(
      _PrefsKeys.currentWater,
      (row['current_water'] as num?)?.toInt() ?? 0,
    );
    await prefs.setInt(
      _PrefsKeys.lastWaterUpdateTime,
      (row['last_water_update_ms'] as num).toInt(),
    );
    await prefs.setInt(
      _PrefsKeys.savedTreesCount,
      (row['saved_trees_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> _applyCigaretteCollection(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    final lcw = row['last_collection_window'] as String?;
    if (lcw != null) {
      await prefs.setString(_PrefsKeys.lastCollectionWindow, lcw);
    } else {
      await prefs.remove(_PrefsKeys.lastCollectionWindow);
    }
    final sw = row['session_window'] as String?;
    if (sw != null) {
      await prefs.setString(_PrefsKeys.sessionWindow, sw);
    } else {
      await prefs.remove(_PrefsKeys.sessionWindow);
    }
    final sa = row['session_asset'] as String?;
    if (sa != null) {
      await prefs.setString(_PrefsKeys.sessionAsset, sa);
    } else {
      await prefs.remove(_PrefsKeys.sessionAsset);
    }
    await prefs.setInt(
      _PrefsKeys.sessionAttempts,
      (row['session_attempts'] as num?)?.toInt() ?? 0,
    );
    final paths = row['collected_asset_paths'];
    final localCollected =
        prefs.getStringList(_PrefsKeys.collectedCigaretteAssets) ?? <String>[];
    // DB 기본 행은 collected_asset_paths 가 [] — pull 이 로컬 수집을 지우지 않도록 한다.
    // 원격에 수집 데이터가 있으면 로컬과 합쳐 멀티 기기·재설치 후에도 잃지 않게 한다.
    if (paths is List && paths.isNotEmpty) {
      final remote = paths.map((e) => e.toString()).toList();
      final merged = {...localCollected, ...remote}.toList()..sort();
      await prefs.setStringList(_PrefsKeys.collectedCigaretteAssets, merged);
    }
  }

  static Future<void> _applyGameStats(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    final best = row['number_sequence_best_seconds'];
    if (best != null) {
      final v = (best as num).toDouble();
      await prefs.setDouble(_PrefsKeys.bestRecord, v);
    } else {
      await prefs.remove(_PrefsKeys.bestRecord);
    }
    await prefs.setInt(
      _PrefsKeys.wordGameLevel,
      (row['word_game_level'] as num?)?.toInt() ?? 1,
    );
    await prefs.setInt(
      _PrefsKeys.timingTapBestScore,
      (row['timing_tap_best_score'] as num?)?.toInt() ?? 0,
    );
    final remoteCatch =
        (row['cigarette_catch_best_stage'] as num?)?.toInt() ?? 0;
    final localCatch =
        prefs.getInt(_PrefsKeys.cigaretteCatchBestStage) ?? 0;
    // DB 기본값 0이 pull 때 로컬 기록을 지우지 않도록 더 큰 값을 유지
    final mergedCatch =
        remoteCatch > localCatch ? remoteCatch : localCatch;
    await prefs.setInt(_PrefsKeys.cigaretteCatchBestStage, mergedCatch);
  }
}
