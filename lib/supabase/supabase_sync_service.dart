import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import '../api/game_stats_prefs.dart';
import '../auth/bff_auth_service.dart';
import '../notifications/daily_reminder_worker.dart' as dw;
import '../data/main_tutorial_prefs.dart';
import '../notifications/pattern_peak_slots.dart';
import 'supabase_config.dart';

/// SharedPreferences 키 — 앱 코드와 동일한 문자열
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
  static const bestRecord = 'bestRecord';
  static const wordGameLevel = 'word_game_level';
  static const timingTapBestScore = 'timing_tap_best_score';
  static const cigaretteCatchBestStage = 'cigarette_catch_best_stage';
  static const cigaretteCatchBestScore = 'cigarette_catch_best_score';
  static const pullPendingAfterLogin = 'supabase_pull_pending_after_login';
  static const lastAuthUid = 'supabase_last_auth_uid';
  static const forceOnboardingOnce = 'supabase_force_onboarding_once';
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

  /// 회원가입 직후 첫 로그인에서는 서버 상태와 무관하게 온보딩을 먼저 진행시킨다.
  static Future<void> markForceOnboardingOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_PrefsKeys.forceOnboardingOnce, true);
  }

  /// 설정에서 「초기 설정으로 돌아가기」 — 로그인·약관은 유지하고 intro만 다시 진행.
  static Future<void> resetOnboardingForIntroReplay() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_PrefsKeys.isConfigured, false);
    for (final key in [
      _PrefsKeys.dailyCigarettes,
      _PrefsKeys.cigarettesPerPack,
      _PrefsKeys.pricePerPack,
      _PrefsKeys.durationDays,
      _PrefsKeys.startTime,
      _PrefsKeys.failureCount,
      _PrefsKeys.lungHealth,
      _PrefsKeys.lastUpdatedTime,
      _PrefsKeys.pinnedReasonText,
      _PrefsKeys.quitReasonsV1,
      _PrefsKeys.selectedReasonId,
      dw.kSelectedReasonTextKey,
      dw.kGoalDaysKey,
      dw.kGoalCongratulatedDayKey,
    ]) {
      await prefs.remove(key);
    }

    await markForceOnboardingOnce();

    if (SupabaseConfig.isConfigured && BffAuthService.instance.isLoggedIn) {
      try {
        await _pushOnboardingResetToRemote(prefs);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('SupabaseSyncService.resetOnboardingForIntroReplay: $e\n$st');
        }
      }
    }
  }

  static Future<void> _pushOnboardingResetToRemote(SharedPreferences prefs) async {
    final headers = await _authHeader();
    if (headers.isEmpty) return;

    final body = <String, dynamic>{
      'quit_profile': {
        'is_configured': false,
        'daily_cigarettes': 0,
        'cigarettes_per_pack': 20,
        'price_per_pack': 4500,
        'duration_days': null,
        'start_time_ms': 0,
        'failure_count': 0,
        'goal_days': null,
        'goal_congratulated_day': null,
        'lung_health': 0,
        'lung_last_updated_ms': null,
        'pinned_reason_text': null,
      },
      'reasons': {
        'reasons_json': <dynamic>[],
        'selected_reason_id': null,
        'selected_reason_text': null,
      },
    };

    final res = await http.put(
      _bffUri('/v1/sync/push'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('onboarding reset push failed: ${res.statusCode}');
    }
  }

  /// 흡연 습관(량·가격·기간)만 갱신 — 금연 시작일·진행 기록은 유지.
  static Future<void> saveHabitSettings({
    required int dailyCigarettes,
    required int cigarettesPerPack,
    required int pricePerPack,
    required int durationDays,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_PrefsKeys.dailyCigarettes, dailyCigarettes);
    await prefs.setInt(_PrefsKeys.cigarettesPerPack, cigarettesPerPack);
    await prefs.setInt(_PrefsKeys.pricePerPack, pricePerPack);
    await prefs.setInt(_PrefsKeys.durationDays, durationDays);
    await prefs.setBool(_PrefsKeys.isConfigured, true);

    try {
      await pushLocalToRemoteIfEligible();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SupabaseSyncService.saveHabitSettings: $e\n$st');
      }
    }
  }

  /// 로그아웃 직전에 현재 로그인 UID를 기록해 다음 로그인 시 계정 전환을 감지한다.
  static Future<void> rememberCurrentAuthUidBeforeSignOut() async {
    if (!SupabaseConfig.isConfigured) return;
    final uid = BffAuthService.instance.userId;
    if (uid == null || uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_PrefsKeys.lastAuthUid, uid);
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

  /// 로그아웃/계정 전환 시 이전 계정 로컬 기록이 다음 계정으로 섞여 들어가는 것을 방지.
  static Future<void> clearLocalStateForAccountSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = <String>[
      kTermsAgreedPrefsKey,
      _PrefsKeys.isConfigured,
      _PrefsKeys.dailyCigarettes,
      _PrefsKeys.cigarettesPerPack,
      _PrefsKeys.pricePerPack,
      _PrefsKeys.durationDays,
      _PrefsKeys.startTime,
      _PrefsKeys.failureCount,
      _PrefsKeys.lungHealth,
      _PrefsKeys.lastUpdatedTime,
      _PrefsKeys.pinnedReasonText,
      _PrefsKeys.quitReasonsV1,
      _PrefsKeys.selectedReasonId,
      _PrefsKeys.bestRecord,
      _PrefsKeys.wordGameLevel,
      _PrefsKeys.timingTapBestScore,
      _PrefsKeys.cigaretteCatchBestStage,
      _PrefsKeys.cigaretteCatchBestScore,
      _PrefsKeys.pullPendingAfterLogin,
      dw.kGoalDaysKey,
      dw.kGoalCongratulatedDayKey,
      dw.kReminderTimesKey,
      dw.kSelectedReasonTextKey,
      dw.kReasonNotificationEnabledKey,
      dw.kInactivityNotificationEnabledKey,
      dw.kCalendarReminderEnabledKey,
      dw.kLastAppOpenTimeMsKey,
      dw.kPatternReminderEnabledKey,
      dw.kPatternReminderSlotsKey,
      kSmokingPatternLogsPrefsKey,
      MainTutorialPrefs.completedKey,
      GameStatsPrefsKeys.numberSequenceLastClearSeconds,
      GameStatsPrefsKeys.timingTapLastSessionScore,
      GameStatsPrefsKeys.cigaretteCatchLastSessionScore,
    ];

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  static Future<void> runPostLoginPullIfNeeded() async {
    while (true) {
      final existing = _postLoginPullInFlight;
      if (existing != null) {
        await existing;
        if (await _needsPostLoginPullNow()) {
          continue;
        }
        return;
      }

      final done = _runPostLoginPullIfNeededBody();
      _postLoginPullInFlight = done;
      try {
        await done;
      } finally {
        _postLoginPullInFlight = null;
      }
      return;
    }
  }

  static Future<bool> _needsPostLoginPullNow() async {
    if (!SupabaseConfig.isConfigured) return false;
    if (!BffAuthService.instance.isLoggedIn) return false;
    final uid = BffAuthService.instance.userId;
    if (uid == null || uid.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final forceOnboarding =
        prefs.getBool(_PrefsKeys.forceOnboardingOnce) ?? false;
    final pending = prefs.getBool(_PrefsKeys.pullPendingAfterLogin) ?? false;
    final initialDone = prefs.getBool(_initialPullDoneKey(uid)) ?? false;
    return forceOnboarding || pending || !initialDone;
  }

  /// 로그인 직후 UI 게이트 진입 전에 현재 사용자 기준으로 로컬 상태를 정렬한다.
  static Future<void> prepareLocalStateForCurrentUser() async {
    if (!SupabaseConfig.isConfigured) return;
    if (!BffAuthService.instance.isLoggedIn) return;
    final uid = BffAuthService.instance.userId;
    if (uid == null || uid.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString(_PrefsKeys.lastAuthUid);
    if (lastUid != null && lastUid.isNotEmpty && lastUid != uid) {
      await clearLocalStateForAccountSwitch();
      await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, true);
    }
    await prefs.setString(_PrefsKeys.lastAuthUid, uid);
  }

  static Future<void> _runPostLoginPullIfNeededBody() async {
    if (!SupabaseConfig.isConfigured) return;
    if (!BffAuthService.instance.isLoggedIn) return;

    final prefs = await SharedPreferences.getInstance();
    final uid = BffAuthService.instance.userId;
    if (uid == null) return;

    final forceOnboarding =
        prefs.getBool(_PrefsKeys.forceOnboardingOnce) ?? false;
    if (forceOnboarding) {
      await prefs.setBool(_PrefsKeys.isConfigured, false);
      await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, false);
      await prefs.setBool(_initialPullDoneKey(uid), true);
      await prefs.setString(_PrefsKeys.lastAuthUid, uid);
      await prefs.setBool(_PrefsKeys.forceOnboardingOnce, false);
      return;
    }

    final lastUid = prefs.getString(_PrefsKeys.lastAuthUid);
    final isAccountSwitched =
        lastUid != null && lastUid.isNotEmpty && lastUid != uid;
    if (isAccountSwitched) {
      await clearLocalStateForAccountSwitch();
      await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, true);
    }

    final pending = prefs.getBool(_PrefsKeys.pullPendingAfterLogin) ?? false;
    final initialDone = prefs.getBool(_initialPullDoneKey(uid)) ?? false;

    try {
      final remoteOnboardingDone = await _remoteOnboardingCompleted();

      if (remoteOnboardingDone == null) {
        // 서버 미응답(네트워크 오류/타임아웃) — pullPendingAfterLogin 을 지우지 않고
        // 다음 기회(앱 재시작·세션 변경)에 재시도한다.
        // 이 플래그를 여기서 지워버리면, 이후 shouldShowIntroFlow() 가
        // 로컬 isConfigured=false 를 보고 인트로를 표시해 기존 데이터를 덮어쓸 수 있다.
        return;
      }

      if (remoteOnboardingDone == false) {
        // 서버에서 온보딩 미완료 — 로컬도 미설정 상태로 맞추고 종료
        await prefs.setBool(_PrefsKeys.isConfigured, false);
        await prefs.setBool(_initialPullDoneKey(uid), true);
        await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, false);
        await prefs.setString(_PrefsKeys.lastAuthUid, uid);
        return;
      }

      // remoteOnboardingDone == true
      if (!pending && initialDone) return;

      await _pullAll(prefs);
      await prefs.setBool(_initialPullDoneKey(uid), true);
      await prefs.setBool(_PrefsKeys.pullPendingAfterLogin, false);
      await prefs.setString(_PrefsKeys.lastAuthUid, uid);
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

  static Future<bool?> remoteOnboardingCompleted() => _remoteOnboardingCompleted();

  /// intro(초기 설정) 화면을 보여줘야 하면 true.
  static Future<bool> shouldShowIntroFlow() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_PrefsKeys.forceOnboardingOnce) ?? false) {
      if (!(prefs.getBool(_PrefsKeys.isConfigured) ?? false)) {
        return true;
      }
      await prefs.setBool(_PrefsKeys.forceOnboardingOnce, false);
    }

    if (SupabaseConfig.isConfigured && BffAuthService.instance.isLoggedIn) {
      final remote = await _remoteOnboardingCompleted();
      if (remote == false) {
        await prefs.setBool(_PrefsKeys.isConfigured, false);
        return true;
      }
      if (remote == true) {
        return false;
      }
      // remote == null: 서버 미응답(네트워크 오류).
      // 로그인된 기존 사용자에게 인트로를 강제 진입시키면 서버 데이터를 덮어쓸 위험이 있다.
      // 신규 계정은 이 분기 도달 전에 forceOnboardingOnce 플래그로 보호된다.
      return false;
    }

    return !(prefs.getBool(_PrefsKeys.isConfigured) ?? false);
  }

  static Future<bool?> _remoteOnboardingCompleted() async {
    final headers = await _authHeader();
    if (headers.isEmpty) return null;
    final res = await http
        .get(_bffUri('/v1/sync/onboarding'), headers: headers)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
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
    final reminderList =
        reminderDecoded is List ? reminderDecoded : <dynamic>[];

    dynamic patternSlotsDecoded;
    final patternSlotsRaw = prefs.getString(dw.kPatternReminderSlotsKey);
    if (patternSlotsRaw != null && patternSlotsRaw.trim().isNotEmpty) {
      try {
        patternSlotsDecoded = jsonDecode(patternSlotsRaw);
      } catch (_) {}
    }
    final patternSlotsList =
        patternSlotsDecoded is List ? patternSlotsDecoded : <dynamic>[];

    final startMs =
        prefs.getInt(_PrefsKeys.startTime) ?? DateTime.now().millisecondsSinceEpoch;
    final lungLast = prefs.getInt(_PrefsKeys.lastUpdatedTime) ?? startMs;

    final body = <String, dynamic>{
      // 신규 통합 quit_profile
      'quit_profile': {
        'is_configured': prefs.getBool(_PrefsKeys.isConfigured) ?? false,
        'daily_cigarettes': prefs.getInt(_PrefsKeys.dailyCigarettes) ?? 0,
        'cigarettes_per_pack': prefs.getInt(_PrefsKeys.cigarettesPerPack) ?? 20,
        'price_per_pack': prefs.getInt(_PrefsKeys.pricePerPack) ?? 4500,
        'duration_days': prefs.getInt(_PrefsKeys.durationDays),
        'start_time_ms': startMs,
        'failure_count': prefs.getInt(_PrefsKeys.failureCount) ?? 0,
        'goal_days': prefs.getInt(dw.kGoalDaysKey),
        'goal_congratulated_day': prefs.getInt(dw.kGoalCongratulatedDayKey),
        'lung_health':
            (prefs.getInt(_PrefsKeys.lungHealth) ?? 100).clamp(0, 100),
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
        'calendar_reminder_enabled':
            prefs.getBool(dw.kCalendarReminderEnabledKey) ?? true,
        'pattern_reminder_enabled':
            prefs.getBool(dw.kPatternReminderEnabledKey) ?? true,
        'pattern_reminder_slots_json': patternSlotsList,
        'last_app_open_time_ms': prefs.getInt(dw.kLastAppOpenTimeMsKey),
      },
      'game_stats': <String, dynamic>{
        'number_sequence_best_seconds': bestSec,
        'word_game_level': prefs.getInt(_PrefsKeys.wordGameLevel) ?? 1,
        'timing_tap_best_score':
            prefs.getInt(_PrefsKeys.timingTapBestScore) ?? 0,
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
      debugPrint('sync push failed: HTTP ${res.statusCode}');
    }
  }

  static Future<void> _pullAll(SharedPreferences prefs) async {
    final headers = await _authHeader();
    if (headers.isEmpty) return;

    final res = await http.get(_bffUri('/v1/sync/pull'), headers: headers);
    if (res.statusCode != 200) return;
    final map = jsonDecode(res.body) as Map<String, dynamic>;

    // 신규 통합 quit_profile (하위 호환: 구 user_settings/quit_progress도 처리)
    final qp = map['quit_profile'] as Map<String, dynamic>?;
    if (qp != null) {
      await _applyQuitProfile(qp, prefs);
    }

    await _applyReasons(
      map['reasons'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyNotificationSettings(
      map['notification_settings'] as Map<String, dynamic>?,
      prefs,
    );
    await _applyGameStats(
      map['game_stats'] as Map<String, dynamic>?,
      prefs,
    );
  }

  static Future<void> _applyQuitProfile(
    Map<String, dynamic> row,
    SharedPreferences prefs,
  ) async {
    final startMs = row['start_time_ms'];
    final hasStartTime = startMs != null && (startMs as num).toInt() > 0;
    final remoteConfigured = row['is_configured'] as bool? ?? false;
    final dailyCigs = (row['daily_cigarettes'] as num?)?.toInt() ?? 0;
    await prefs.setBool(
      _PrefsKeys.isConfigured,
      remoteConfigured && hasStartTime && dailyCigs > 0,
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

    if (startMs != null) {
      await prefs.setInt(
          _PrefsKeys.startTime, (startMs as num).toInt());
    }
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
    final lungLast = row['lung_last_updated_ms'];
    if (lungLast != null) {
      await prefs.setInt(
          _PrefsKeys.lastUpdatedTime, (lungLast as num).toInt());
    }
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

    // calendar_reminder_enabled (신규) — 하위 호환: attendance_reminder_enabled도 수용
    final calendarEnabled = (row['calendar_reminder_enabled'] ??
            row['attendance_reminder_enabled']) as bool? ??
        true;
    await prefs.setBool(dw.kCalendarReminderEnabledKey, calendarEnabled);

    final patternReminderEnabled =
        row['pattern_reminder_enabled'] as bool? ?? true;
    await prefs.setBool(dw.kPatternReminderEnabledKey, patternReminderEnabled);

    List<dynamic>? serverPatternList;
    final remotePatternSlots = row['pattern_reminder_slots_json'];
    if (remotePatternSlots != null) {
      if (remotePatternSlots is List) {
        serverPatternList = remotePatternSlots;
      } else {
        try {
          final decoded = jsonDecode(jsonEncode(remotePatternSlots));
          if (decoded is List) serverPatternList = decoded;
        } catch (_) {}
      }
    }
    final serverHasPatternSlots =
        serverPatternList != null && serverPatternList.isNotEmpty;

    final patternLogs = decodeSmokingPatternLogs(
      prefs.getString(kSmokingPatternLogsPrefsKey),
    );
    final hasLocalPatternData =
        countRecentPatternLogs(patternLogs) >= kPatternMinLogs;

    if (!patternReminderEnabled) {
      try {
        await dw.cancelPatternReminders();
      } catch (_) {}
      await prefs.remove(dw.kPatternReminderSlotsKey);
      unawaited(pushLocalToRemoteIfEligible());
    } else if (hasLocalPatternData) {
      if (serverHasPatternSlots) {
        try {
          await prefs.setString(
            dw.kPatternReminderSlotsKey,
            jsonEncode(serverPatternList),
          );
        } catch (_) {}
      } else {
        var localHasPatternSlots = false;
        final localPatternRaw = prefs.getString(dw.kPatternReminderSlotsKey);
        if (localPatternRaw != null && localPatternRaw.trim().isNotEmpty) {
          try {
            final loc = jsonDecode(localPatternRaw);
            localHasPatternSlots = loc is List && loc.isNotEmpty;
          } catch (_) {}
        }
        if (localHasPatternSlots) {
          unawaited(pushLocalToRemoteIfEligible());
        }
      }
    } else if (serverHasPatternSlots) {
      // 재설치 등으로 로컬 기록은 없지만 서버에 슬롯이 남아 있는 경우 복구
      try {
        await prefs.setString(
          dw.kPatternReminderSlotsKey,
          jsonEncode(serverPatternList),
        );
      } catch (_) {}
    } else {
      await dw.clearPatternReminderSlots();
      await dw.cancelPatternReminders();
    }

    if (patternReminderEnabled) {
      try {
        final slots = await dw.getPatternReminderSlots();
        if (slots.isEmpty) {
          await dw.cancelPatternReminders();
        } else {
          final nickname = prefs.getString('nickname')?.trim();
          await dw.schedulePatternRemindersFromSlots(
            slots: slots,
            nickname:
                (nickname != null && nickname.isNotEmpty) ? nickname : '회원',
          );
        }
      } catch (_) {}
    }

    final lastMs = row['last_app_open_time_ms'];
    if (lastMs != null) {
      await prefs.setInt(
          dw.kLastAppOpenTimeMsKey, (lastMs as num).toInt());
    } else {
      await prefs.remove(dw.kLastAppOpenTimeMsKey);
    }

    try {
      await dw.scheduleAllDailyReminders();
    } catch (_) {}

    if (!calendarEnabled) {
      try {
        await dw.cancelCalendarReminder();
      } catch (_) {}
    }
  }

  static Future<void> _applyGameStats(
    Map<String, dynamic>? row,
    SharedPreferences prefs,
  ) async {
    if (row == null) return;
    final best = row['number_sequence_best_seconds'];
    if (best != null) {
      await prefs.setDouble(_PrefsKeys.bestRecord, (best as num).toDouble());
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
    final localCatch = prefs.getInt(_PrefsKeys.cigaretteCatchBestStage) ?? 0;
    await prefs.setInt(
      _PrefsKeys.cigaretteCatchBestStage,
      remoteCatch > localCatch ? remoteCatch : localCatch,
    );
    final remoteCatchScore =
        (row['cigarette_catch_best_score'] as num?)?.toInt() ?? 0;
    final localCatchScore =
        prefs.getInt(_PrefsKeys.cigaretteCatchBestScore) ?? 0;
    await prefs.setInt(
      _PrefsKeys.cigaretteCatchBestScore,
      remoteCatchScore > localCatchScore ? remoteCatchScore : localCatchScore,
    );

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
