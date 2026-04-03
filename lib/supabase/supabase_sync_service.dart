import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import '../api/game_stats_prefs.dart';
import '../api/remote_assets.dart';
import '../auth/bff_auth_service.dart';
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
  static const cigaretteCatchBestScore = 'cigarette_catch_best_score';
  static const pullPendingAfterLogin = 'supabase_pull_pending_after_login';
}

String _initialPullDoneKey(String uid) => 'supabase_initial_pull_done_$uid';

Uri _bffUri(String path) {
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  return Uri.parse('$base$path');
}

Future<Map<String, String>> _authHeader() async {
  final t = await BffAuthService.instance.getValidAccessToken();
  if (t == null || t.isEmpty) return {};
  return {
    'Authorization': 'Bearer $t',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}

/// 로컬(SharedPreferences)과 서버(BFF → Supabase) 간 동기화.
abstract final class SupabaseSyncService {
  static Future<void>? _postLoginPullInFlight;

  static Future<void> markPullRequiredOnNextLogin() async {
    if (!SupabaseConfig.isConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, true);
  }

  static Future<void> runStartupPushOnlyIfEligible() async {
    if (!SupabaseConfig.isConfigured) return;
    if (!BffAuthService.instance.isLoggedIn) return;

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
    if (!BffAuthService.instance.isLoggedIn) return;

    final prefs = await SharedPreferences.getInstance();
    final uid = BffAuthService.instance.userId;
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

  static Future<void> pushLocalToRemoteIfEligible() async {
    if (!SupabaseConfig.isConfigured) return;
    if (!BffAuthService.instance.isLoggedIn) return;

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

  static Future<bool> _remoteOnboardingCompleted() async {
    final headers = await _authHeader();
    if (headers.isEmpty) return false;
    final res = await http.get(_bffUri('/v1/sync/onboarding'), headers: headers);
    if (res.statusCode != 200) return false;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return map['is_configured'] == true;
  }

  static Future<void> _pushAll(SharedPreferences prefs) async {
    final headers = await _authHeader();
    if (headers.isEmpty) return;

    final best = prefs.getDouble(_PrefsKeys.bestRecord);
    double? bestSec;
    if (best != null && best.isFinite && !best.isNaN) {
      bestSec = best;
    }

    dynamic reasonDecoded;
    final rawReason = prefs.getString(_PrefsKeys.quitReasonsV1);
    if (rawReason != null && rawReason.trim().isNotEmpty) {
      try {
        reasonDecoded = jsonDecode(rawReason);
      } catch (_) {}
    }
    final reasonsList = reasonDecoded is List ? reasonDecoded : <dynamic>[];

    dynamic reminderDecoded;
    final reminderRaw = prefs.getString(dw.kReminderTimesKey);
    if (reminderRaw != null && reminderRaw.trim().isNotEmpty) {
      try {
        reminderDecoded = jsonDecode(reminderRaw);
      } catch (_) {}
    }
    final reminderList = reminderDecoded is List ? reminderDecoded : <dynamic>[];

    final lastDateStr = prefs.getString(att.kAttendanceLastDateKey);

    final startMs = prefs.getInt(_PrefsKeys.startTime) ??
        DateTime.now().millisecondsSinceEpoch;
    final lungLast =
        prefs.getInt(_PrefsKeys.lastUpdatedTime) ?? startMs;

    final body = <String, dynamic>{
      'user_settings': {
        'is_configured': prefs.getBool(_PrefsKeys.isConfigured) ?? false,
        'daily_cigarettes': prefs.getInt(_PrefsKeys.dailyCigarettes) ?? 0,
        'cigarettes_per_pack': prefs.getInt(_PrefsKeys.cigarettesPerPack) ?? 20,
        'price_per_pack': prefs.getInt(_PrefsKeys.pricePerPack) ?? 4500,
        'duration_days': prefs.getInt(_PrefsKeys.durationDays),
      },
      'quit_progress': {
        'start_time_ms': startMs,
        'failure_count': prefs.getInt(_PrefsKeys.failureCount) ?? 0,
        'goal_days': prefs.getInt(dw.kGoalDaysKey),
        'goal_congratulated_day': prefs.getInt(dw.kGoalCongratulatedDayKey),
        'lung_health': (prefs.getInt(_PrefsKeys.lungHealth) ?? 100).clamp(0, 100),
        'lung_last_updated_ms': lungLast,
        'pinned_reason_text': prefs.getString(_PrefsKeys.pinnedReasonText),
      },
      'reasons': {
        'reasons_json': reasonsList,
        'selected_reason_id': prefs.getString(_PrefsKeys.selectedReasonId),
        'selected_reason_text': prefs.getString(dw.kSelectedReasonTextKey),
      },
      'notification_settings': {
        'reminder_times_json': reminderList,
        'reason_notification_enabled':
            prefs.getBool(dw.kReasonNotificationEnabledKey) ?? false,
        'inactivity_notification_enabled':
            prefs.getBool(dw.kInactivityNotificationEnabledKey) ?? true,
        'attendance_reminder_enabled':
            prefs.getBool(dw.kAttendanceReminderEnabledKey) ?? true,
        'cigarette_collection_reminder_enabled':
            prefs.getBool(dw.kCigaretteCollectionReminderEnabledKey) ?? true,
        'last_app_open_time_ms': prefs.getInt(dw.kLastAppOpenTimeMsKey),
      },
      'coins_and_attendance': {
        'golden_coins': prefs.getInt(att.kGoldenCoinsKey) ?? 0,
        'attendance_streak_day': prefs.getInt(att.kAttendanceStreakDayKey) ?? 1,
        'attendance_last_date': lastDateStr,
      },
      'tree_progress': {
        'growth_stage': prefs.getInt(_PrefsKeys.growthStage) ?? 1,
        'water': prefs.getInt(_PrefsKeys.water) ?? 0,
        'current_water': prefs.getInt(_PrefsKeys.currentWater) ?? 0,
        'last_water_update_ms': prefs.getInt(_PrefsKeys.lastWaterUpdateTime) ??
            DateTime.now().millisecondsSinceEpoch,
        'saved_trees_count': prefs.getInt(_PrefsKeys.savedTreesCount) ?? 0,
      },
      'cigarette_collection': {
        'last_collection_window': prefs.getString(_PrefsKeys.lastCollectionWindow),
        'session_window': prefs.getString(_PrefsKeys.sessionWindow),
        'session_asset': prefs.getString(_PrefsKeys.sessionAsset),
        'session_attempts': prefs.getInt(_PrefsKeys.sessionAttempts) ?? 0,
        'collected_asset_paths': RemoteAssets.normalizeCigaretteKeyList(
          prefs.getStringList(_PrefsKeys.collectedCigaretteAssets) ?? <String>[],
        ),
      },
      'game_stats': <String, dynamic>{
        'number_sequence_best_seconds': bestSec,
        'word_game_level': prefs.getInt(_PrefsKeys.wordGameLevel) ?? 1,
        'timing_tap_best_score': prefs.getInt(_PrefsKeys.timingTapBestScore) ?? 0,
        'cigarette_catch_best_stage':
            prefs.getInt(_PrefsKeys.cigaretteCatchBestStage) ?? 0,
        'cigarette_catch_best_score':
            prefs.getInt(_PrefsKeys.cigaretteCatchBestScore) ?? 0,
        if (prefs.containsKey(GameStatsPrefsKeys.numberSequenceLastClearSeconds))
          'number_sequence_last_clear_seconds': prefs.getDouble(
            GameStatsPrefsKeys.numberSequenceLastClearSeconds,
          ),
        if (prefs.containsKey(GameStatsPrefsKeys.timingTapLastSessionScore))
          'timing_tap_last_session_score':
              prefs.getInt(GameStatsPrefsKeys.timingTapLastSessionScore),
        if (prefs.containsKey(GameStatsPrefsKeys.cigaretteCatchLastSessionScore))
          'cigarette_catch_last_session_score':
              prefs.getInt(GameStatsPrefsKeys.cigaretteCatchLastSessionScore),
      },
    };

    final res = await http.put(
      _bffUri('/v1/sync/push'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && kDebugMode) {
      debugPrint('sync push failed ${res.statusCode} ${res.body}');
    }
  }

  static Future<void> _pullAll(SharedPreferences prefs) async {
    final headers = await _authHeader();
    if (headers.isEmpty) return;

    final res = await http.get(_bffUri('/v1/sync/pull'), headers: headers);
    if (res.statusCode != 200) return;
    final map = jsonDecode(res.body) as Map<String, dynamic>;

    await _applyUserSettings(
      map['user_settings'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyQuitProgress(
      map['quit_progress'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyReasons(
      map['reasons'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyNotificationSettings(
      map['notification_settings'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyCoinsAndAttendance(
      map['coins_and_attendance'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyTreeProgress(
      map['tree_progress'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyCigaretteCollection(
      map['cigarette_collection'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyGameStats(
      map['game_stats'] as Map<String, dynamic>?,
      prefs,
    );
  }

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
      // 서버·DB 기본값이 [] 인 경우, 로그인 직후 pull 이 로컬에 저장된 알림 시간을
      // 덮어써 전부 사라지는 문제가 있음 → 빈 서버는 로컬이 비어 있을 때만 적용.
      List<dynamic>? serverList;
      if (j is List) {
        serverList = j;
      } else {
        try {
          final decoded = jsonDecode(jsonEncode(j));
          if (decoded is List) serverList = decoded;
        } catch (_) {}
      }
      final serverEmpty = serverList == null || serverList.isEmpty;
      if (!serverEmpty) {
        await prefs.setString(dw.kReminderTimesKey, jsonEncode(j));
      } else {
        var localHasReminders = false;
        final localRaw = prefs.getString(dw.kReminderTimesKey);
        if (localRaw != null && localRaw.trim().isNotEmpty) {
          try {
            final loc = jsonDecode(localRaw);
            localHasReminders = loc is List && loc.isNotEmpty;
          } catch (_) {}
        }
        if (!localHasReminders) {
          await prefs.setString(dw.kReminderTimesKey, jsonEncode(j));
        } else {
          unawaited(pushLocalToRemoteIfEligible());
        }
      }
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
    final hasLocalCollectionPref =
        prefs.containsKey(dw.kCigaretteCollectionReminderEnabledKey);
    final remoteCollectionEnabled =
        row['cigarette_collection_reminder_enabled'] as bool?;
    if (remoteCollectionEnabled == false && !hasLocalCollectionPref) {
      // 최초 동기화에서 DB 기본값/과거 데이터 false가 내려온 경우, 앱 기본 정책(true)로 복구
      // 이후 pushLocalToRemoteIfEligible()가 DB서버 값을 true로 정정합니다.
      await prefs.setBool(dw.kCigaretteCollectionReminderEnabledKey, true);
      unawaited(pushLocalToRemoteIfEligible());
    } else {
      await prefs.setBool(
        dw.kCigaretteCollectionReminderEnabledKey,
        remoteCollectionEnabled ?? true,
      );
    }
    final lastMs = row['last_app_open_time_ms'];
    if (lastMs != null) {
      await prefs.setInt(dw.kLastAppOpenTimeMsKey, (lastMs as num).toInt());
    } else {
      await prefs.remove(dw.kLastAppOpenTimeMsKey);
    }
    try {
      await dw.scheduleAllDailyReminders();
    } catch (_) {}
    try {
      await dw.scheduleCigaretteCollectionReminders();
    } catch (_) {}
    if (!(row['attendance_reminder_enabled'] as bool? ?? true)) {
      try {
        await dw.cancelAttendanceReminder();
      } catch (_) {}
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
      await prefs.setString(
        _PrefsKeys.sessionAsset,
        RemoteAssets.normalizeCigaretteKey(sa),
      );
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
    if (paths is List && paths.isNotEmpty) {
      final remote = paths
          .map((e) => RemoteAssets.normalizeCigaretteKey(e.toString()))
          .toList();
      final localNorm =
          localCollected.map(RemoteAssets.normalizeCigaretteKey).toList();
      final merged = {...localNorm, ...remote}.toList()..sort();
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
    final mergedCatch =
        remoteCatch > localCatch ? remoteCatch : localCatch;
    await prefs.setInt(_PrefsKeys.cigaretteCatchBestStage, mergedCatch);
    final remoteCatchScore =
        (row['cigarette_catch_best_score'] as num?)?.toInt() ?? 0;
    final localCatchScore =
        prefs.getInt(_PrefsKeys.cigaretteCatchBestScore) ?? 0;
    final mergedCatchScore =
        remoteCatchScore > localCatchScore ? remoteCatchScore : localCatchScore;
    await prefs.setInt(_PrefsKeys.cigaretteCatchBestScore, mergedCatchScore);

    final lastClear = row['number_sequence_last_clear_seconds'];
    if (lastClear != null) {
      await prefs.setDouble(
        GameStatsPrefsKeys.numberSequenceLastClearSeconds,
        (lastClear as num).toDouble(),
      );
    } else {
      await prefs.remove(GameStatsPrefsKeys.numberSequenceLastClearSeconds);
    }

    final tapSess = row['timing_tap_last_session_score'];
    if (tapSess != null) {
      await prefs.setInt(
        GameStatsPrefsKeys.timingTapLastSessionScore,
        (tapSess as num).toInt(),
      );
    } else {
      await prefs.remove(GameStatsPrefsKeys.timingTapLastSessionScore);
    }

    final catchSess = row['cigarette_catch_last_session_score'];
    if (catchSess != null) {
      await prefs.setInt(
        GameStatsPrefsKeys.cigaretteCatchLastSessionScore,
        (catchSess as num).toInt(),
      );
    } else {
      await prefs.remove(GameStatsPrefsKeys.cigaretteCatchLastSessionScore);
    }
  }
}
