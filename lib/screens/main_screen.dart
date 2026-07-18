import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_nav.dart';
import '../supabase/supabase_sync_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../api/bff_profile_api.dart';
import '../auth/bff_auth_service.dart';

import 'reminder_settings_screen.dart';
import 'habit_settings_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';
import '../ad_unit_ids.dart';
import '../widgets/app_card.dart';
import '../widgets/future_savings_section.dart';
import '../widgets/goal_celebration_dialog.dart';
import '../widgets/home_hero_card.dart';
import '../widgets/action_list_tile.dart';
import '../widgets/section_header.dart';
import '../data/quit_mode_prefs.dart';
import '../screens/quit_mode_settings_screen.dart';
import '../services/smoking_record_flow.dart';
import '../widgets/sos_overlay.dart';
import '../widgets/smoking_record_sheet.dart';
import 'quit_room/quit_room_list_screen.dart';
import 'quit_room/quit_room_models.dart';
import '../services/quit_room_post_service.dart';
import '../services/quit_room_stats_loader.dart';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

// ✅ WorkManager 알림(네 프로젝트 구조 기준)
import '../notifications/daily_reminder_worker.dart';
import '../notifications/pattern_peak_slots.dart';
// ✅ 홈 화면 위젯 갱신(동기화)
import '../widget/widget_helper.dart';
import '../supabase/supabase_config.dart';
import '../api/reasons_api_service.dart';
import '../api/smoking_pattern_api_service.dart';

/// 스토어 앱 페이지 (지인 추천 · 공유용)
const String _kAppPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.cjw.nonsmoking';

/// 금연 시작일로부터 현재까지 경과 일수 (1일차부터 카운트)
int quitCalendarDayNumber(DateTime startTime) {
  final days = DateTime.now().difference(startTime).inDays;
  return days < 0 ? 0 : days + 1;
}

class MainScreen extends StatefulWidget {
  final VoidCallback? onResetTap;
  final int? refreshTrigger;

  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;
  final Future<void> Function()? onShowTutorial;

  /// 최초 튜토리얼 스포트라이트용 (없으면 KeyedSubtree 미사용).
  final GlobalKey? tutorialStatsCardKey;
  final GlobalKey? tutorialSosButtonKey;
  final GlobalKey? tutorialSmokedButtonKey;
  final GlobalKey? tutorialReminderButtonKey;

  /// 튜토리얼에서 기록 버튼 노출 등 스크롤 조정용 (선택).
  final ScrollController? mainScrollController;

  const MainScreen({
    super.key,
    this.onResetTap,
    this.refreshTrigger,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
    this.onShowTutorial,
    this.tutorialStatsCardKey,
    this.tutorialSosButtonKey,
    this.tutorialSmokedButtonKey,
    this.tutorialReminderButtonKey,
    this.mainScrollController,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _SmokingPatternLog {
  final int id;
  final String action; // smoked | craving
  final int hour;
  final int minute;
  final String timeLabel;
  final String situation;
  final String emotion;
  final int tsMs;

  const _SmokingPatternLog({
    required this.id,
    required this.action,
    required this.hour,
    required this.minute,
    required this.timeLabel,
    required this.situation,
    required this.emotion,
    required this.tsMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'hour': hour,
        'minute': minute,
        'timeLabel': timeLabel,
        'situation': situation,
        'emotion': emotion,
        'tsMs': tsMs,
      };
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  double _savedMoney = 0;
  int _skippedCigarettes = 0;
  int _failureCount = 0;
  int? _goalDays;
  QuitMode _quitMode = QuitMode.continuous;
  bool _goalCelebrationShowing = false;
  Timer? _timer;
  List<TimeOfDay> _reminderTimes = [];
  String _mainReason = '';
  bool _showReasonEditor = true;
  final TextEditingController _reasonController = TextEditingController();
  final FocusNode _reasonFocusNode = FocusNode();

  BannerAd? _bannerAd;
  bool _isBannerReady = false;
  Timer? _bannerRetryTimer;

  final _moneyFormatter = NumberFormat.decimalPattern('ko_KR');
  final ReasonsApiService _reasonsApi = const ReasonsApiService();
  final SmokingPatternApiService _smokingPatternApi = const SmokingPatternApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppAnalytics.screen('main_screen');
    _loadPersistedData();
    _loadBannerAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      syncWidgetData();
    } else if (state == AppLifecycleState.resumed) {
      _refreshQuitMetricsDisplay();
    }
  }

  void _loadBannerAd() {
    _bannerRetryTimer?.cancel();
    final banner = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint(
              'Banner failed to load: code=${error.code} domain=${error.domain} message=${error.message}',
            );
          }
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _isBannerReady = false;
          });
          _scheduleBannerRetry();
        },
      ),
    );
    banner.load();
  }

  void _scheduleBannerRetry() {
    if (_bannerRetryTimer?.isActive ?? false) return;
    _bannerRetryTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _isBannerReady) return;
      _loadBannerAd();
    });
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      unawaited(_reloadReminderTimesFromPrefs());
    }
    if (oldWidget.dailyCigarettes != widget.dailyCigarettes ||
        oldWidget.pricePerPack != widget.pricePerPack ||
        oldWidget.cigarettesPerPack != widget.cigarettesPerPack) {
      _refreshQuitMetricsDisplay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _bannerRetryTimer?.cancel();
    _bannerAd?.dispose();
    _reasonController.dispose();
    _reasonFocusNode.dispose();
    super.dispose();
  }

  static const String _failureCountKey = 'failureCount';

  /// prefs 기준으로 알림 개수 라벨 동기화 (설정 화면 pop 직후·다른 탭 복귀 등)
  Future<void> _reloadReminderTimesFromPrefs() async {
    final fresh = await getReminderTimes();
    if (!mounted) return;
    setState(() => _reminderTimes = fresh);
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final millis = prefs.getInt('startTime');
    _failureCount = prefs.getInt(_failureCountKey) ?? 0;
    _quitMode = await QuitModePrefs.getMode(prefs);
    if (!prefs.containsKey(QuitModePrefs.quitModeKey)) {
      await prefs.setString(
        QuitModePrefs.quitModeKey,
        QuitMode.continuous.storageValue,
      );
    }
    _mainReason = prefs.getString('pinnedReasonText') ?? '';
    _reasonController.text = _mainReason;
    _showReasonEditor = _mainReason.isEmpty;
    final savedGoal = prefs.getInt(kGoalDaysKey);
    _goalDays = savedGoal != null && savedGoal > 0 ? savedGoal : null;

    // 로컬 우선 표시 후, 로그인 상태면 서버 값으로 동기화(느려도 UI 블로킹 없음)
    unawaited(_syncMainReasonFromApiIfAvailable());

    if (millis != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(millis);
      await QuitModePrefs.ensureOriginStartTime(millis, prefs: prefs);
    } else {
      _startTime = DateTime.now();
      await prefs.setInt('startTime', _startTime!.millisecondsSinceEpoch);
    }

    // 알림 스케줄이 실패·지연돼도 금연 수치·타이머는 바로 동작하도록 먼저 갱신
    _refreshQuitMetricsDisplay();
    _startTimer();

    _reminderTimes = await getReminderTimes();
    if (!mounted) return;
    // Activity·첫 프레임 준비 후 한 번만 부트스트랩 (initState 직후와 AttendanceGate와 중복 호출 시
    // 서로 cancel/재예약이 겹칠 수 있음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        try {
          await bootstrapCoreReminderSchedulesOnAppOpen();
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('MainScreen: bootstrap reminders failed: $e\n$st');
          }
        }
      }());
    });
    await syncWidgetData();
  }

  Future<void> _syncMainReasonFromApiIfAvailable() async {
    if (!SupabaseConfig.isConfigured) return;
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token == null || token.isEmpty) return;
    try {
      final serverPinned = await _reasonsApi.fetchPinnedReason(accessToken: token);
      if (serverPinned == null || serverPinned.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pinnedReasonText', serverPinned);
      await syncWidgetData();
      if (!mounted) return;
      setState(() {
        _mainReason = serverPinned;
        _reasonController.text = serverPinned;
      });
    } catch (_) {
      // 로컬 우선 정책: 서버 실패 시 조용히 무시
    }
  }

  /// 시작 시각 기준 금연 시간·절약·개비 (미래 시각이면 0으로 클램프)
  void _refreshQuitMetricsDisplay() {
    if (_startTime == null || !mounted) return;
    final now = DateTime.now();
    var diff = now.difference(_startTime!);
    if (diff.isNegative) diff = Duration.zero;
    final seconds = diff.inSeconds;

    final totalCigs = (widget.dailyCigarettes / (24 * 60 * 60)) * seconds;

    final costPerCig = widget.cigarettesPerPack > 0
        ? widget.pricePerPack / widget.cigarettesPerPack
        : 0.0;

    final money = totalCigs * costPerCig;

    setState(() {
      _elapsed = diff;
      _savedMoney = money;
      _skippedCigarettes = totalCigs.floor();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime == null) return;
      if (!mounted) {
        _timer?.cancel();
        return;
      }

      final now = DateTime.now();
      var diff = now.difference(_startTime!);
      if (diff.isNegative) diff = Duration.zero;
      final seconds = diff.inSeconds;

      final totalCigs = (widget.dailyCigarettes / (24 * 60 * 60)) * seconds;

      final costPerCig = widget.cigarettesPerPack > 0
          ? widget.pricePerPack / widget.cigarettesPerPack
          : 0.0;

      final money = totalCigs * costPerCig;

      setState(() {
        _elapsed = diff;
        _savedMoney = money;
        _skippedCigarettes = totalCigs.floor();
      });

      // 목표일 도달 시 축하 알림 (한 번만) — 누적일과 동일하게 달력 일차 기준
      final goalDaysElapsed = quitCalendarDayNumber(_startTime!);
      if (_goalDays != null && goalDaysElapsed >= _goalDays!) {
        unawaited(_maybeCelebrateGoal(goalDaysElapsed));
      }

      // 위젯 데이터도 주기적으로 동기화 (대략 1분마다)
      if (seconds % 60 == 0) {
        syncWidgetData();
      }
    });
  }

  Future<void> _maybeCelebrateGoal(int goalDaysElapsed) async {
    if (_goalDays == null || goalDaysElapsed < _goalDays!) return;
    if (_goalCelebrationShowing) return;

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(kGoalCongratulatedDayKey);
    if (last != null && last >= _goalDays!) return;

    _goalCelebrationShowing = true;
    await prefs.setInt(kGoalCongratulatedDayKey, _goalDays!);

    if (!mounted) {
      _goalCelebrationShowing = false;
      return;
    }
    try {
      await showGoalCelebrationDialog(
        context,
        goalDays: _goalDays!,
        savedMoney: _savedMoney,
        skippedCigarettes: _skippedCigarettes,
      );
      if (mounted) {
        await showGoalReachedNotificationIfNeeded(goalDaysElapsed, _goalDays);
      }
    } finally {
      _goalCelebrationShowing = false;
    }
  }

  Future<void> _pickGoalDays() async {
    final ctx = context;
    final prefs = await SharedPreferences.getInstance();
    if (!ctx.mounted) return;
    final picked = await showDialog<int>(
      context: ctx,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('목표일 설정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in const [
                  (7, '7일'),
                  (14, '14일'),
                  (30, '30일'),
                  (60, '60일'),
                  (90, '90일'),
                  (365, '365일 (1년)'),
                  (730, '730일 (2년)'),
                  (1095, '1,095일 (3년)'),
                  (1825, '1,825일 (5년)'),
                ])
                  ListTile(
                    title: Text(option.$2),
                    onTap: () => Navigator.pop(ctx, option.$1),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('해제'),
            ),
          ],
        );
      },
    );
    if (!ctx.mounted) return;
    if (picked == null) return;
    if (picked == 0) {
      await prefs.remove(kGoalDaysKey);
      await prefs.remove(kGoalCongratulatedDayKey);
      if (!ctx.mounted) return;
      setState(() => _goalDays = null);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('목표일을 해제했습니다.'), duration: Duration(seconds: 2)),
      );
    } else {
      await prefs.setInt(kGoalDaysKey, picked);
      await prefs.remove(kGoalCongratulatedDayKey);
      if (!ctx.mounted) return;
      setState(() => _goalDays = picked);
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('목표일을 ${picked}일로 설정했습니다.'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _openReminderSettings() async {
    await Navigator.push<List<TimeOfDay>>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderSettingsScreen(
          initialTimes: List.from(_reminderTimes),
          onUpdated: (list) => setState(() => _reminderTimes = list),
        ),
      ),
    );
    await _reloadReminderTimesFromPrefs();
  }

  Future<void> _saveMainReasonFromInput() async {
    final previousPinned = _mainReason.trim();
    final text = _reasonController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (text.isEmpty) {
      await prefs.remove('pinnedReasonText');
    } else {
      await prefs.setString('pinnedReasonText', text);
      await _upsertPinnedReasonInReasonList(
        prefs,
        text,
        previousPinnedText: previousPinned,
      );
      await _syncSelectedNotificationTextIfPinnedItemEdited(prefs, text);
    }
    if (!mounted) return;
    setState(() {
      _mainReason = text;
      _showReasonEditor = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('금연할 이유를 저장했습니다.')),
    );

    await syncWidgetData();

    // 로컬 반영을 먼저 끝낸 뒤, 서버에 비동기 전송
    unawaited(_pushMainReasonToApiIfAvailable(text));
  }

  Future<void> _pushMainReasonToApiIfAvailable(String text) async {
    if (text.trim().isEmpty) return;
    if (!SupabaseConfig.isConfigured) return;
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token == null || token.isEmpty) return;
    try {
      await _reasonsApi.savePinnedReason(accessToken: token, text: text.trim());
    } catch (_) {
      // 로컬 우선 정책: 서버 실패 시 조용히 무시
    }
  }

  /// 메인에서 대표 이유를 저장할 때: **기존 고정 항목의 문구를 바꾸는 것**이 우선(중복 행 추가 방지).
  Future<void> _upsertPinnedReasonInReasonList(
    SharedPreferences prefs,
    String text, {
    String previousPinnedText = '',
  }) async {
    const reasonsKey = 'quitReasons_v1';
    final raw = prefs.getString(reasonsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      } catch (_) {
        items = <Map<String, dynamic>>[];
      }
    }

    int? targetIndex;
    for (var i = 0; i < items.length; i++) {
      if (items[i]['pinned'] == true) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == null && previousPinnedText.isNotEmpty) {
      for (var i = 0; i < items.length; i++) {
        final t = (items[i]['text'] as String?)?.trim() ?? '';
        if (t == previousPinnedText) {
          targetIndex = i;
          break;
        }
      }
    }

    for (final it in items) {
      it['pinned'] = false;
    }

    if (targetIndex != null) {
      final target = items[targetIndex];
      target['text'] = normalized;
      target['pinned'] = true;
      target['createdAt'] = (target['createdAt'] as int?) ?? now;
      target['displayNumber'] = (target['displayNumber'] as int?) ?? 1;
    } else {
      Map<String, dynamic>? sameText;
      for (final it in items) {
        final t = (it['text'] as String?)?.trim() ?? '';
        if (t == normalized) {
          sameText = it;
          break;
        }
      }
      if (sameText != null) {
        sameText['text'] = normalized;
        sameText['pinned'] = true;
        sameText['createdAt'] = (sameText['createdAt'] as int?) ?? now;
        sameText['displayNumber'] = (sameText['displayNumber'] as int?) ?? 1;
      } else {
        var nextDisplayNumber = 1;
        for (final it in items) {
          final n = (it['displayNumber'] as int?) ?? 0;
          if (n >= nextDisplayNumber) nextDisplayNumber = n + 1;
        }
        items.add(<String, dynamic>{
          'id': now.toString(),
          'text': normalized,
          'pinned': true,
          'createdAt': now,
          'displayNumber': nextDisplayNumber,
        });
      }
    }

    await prefs.setString(reasonsKey, jsonEncode(items));
  }

  /// 알림에 쓰는 이유(종 아이콘)가 대표 이유와 같은 항목이면, 문구만 바뀌어도 알림 문구를 맞춤.
  Future<void> _syncSelectedNotificationTextIfPinnedItemEdited(
    SharedPreferences prefs,
    String newPinnedText,
  ) async {
    const reasonsKey = 'quitReasons_v1';
    const selectedIdKey = 'selectedReasonId';
    final raw = prefs.getString(reasonsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final items = decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      Map<String, dynamic>? pinned;
      for (final it in items) {
        if (it['pinned'] == true) {
          pinned = it;
          break;
        }
      }
      if (pinned == null) return;
      final pid = pinned['id'] as String?;
      final sel = prefs.getString(selectedIdKey);
      if (pid == null || sel == null || pid != sel) return;
      await prefs.setString(kSelectedReasonTextKey, newPinnedText.trim());
      if (prefs.getBool(kReasonNotificationEnabledKey) == true) {
        await scheduleReasonReminder();
      }
    } catch (_) {}
  }

  void _openReasonEditorInline() {
    setState(() {
      _showReasonEditor = true;
      _reasonController.text = _mainReason;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reasonFocusNode.requestFocus();
    });
  }

  Future<String?> _resolveNicknameForPatternNotification() async {
    final cached = await BffProfileApi.readCachedDisplayNameForCurrentUser();
    if (cached != null && cached.isNotEmpty) return cached;
    final prefs = await SharedPreferences.getInstance();
    final fallback = prefs.getString('nickname');
    return fallback;
  }

  Future<void> _savePatternAndSchedule(_SmokingPatternLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kSmokingPatternLogsPrefsKey);
    final list = decodeSmokingPatternLogs(raw);
    list.add(log.toJson());
    if (list.length > 200) {
      list.removeRange(0, list.length - 200);
    }
    await prefs.setString(kSmokingPatternLogsPrefsKey, jsonEncode(list));

    // 이 지점까지 완료되면 흡연(패턴) 기록은 이미 기기에 저장된 상태다.
    // 이후 단계는 로컬 알림 예약·취소이며, OS 권한/플러그인 이슈로 실패해도
    // "저장 실패"로 보이면 안 되므로 별도로 잡아 메시지로만 안내한다.
    try {
      final recentPatternCount = countRecentPatternLogs(list);

      final nickname = await _resolveNicknameForPatternNotification() ?? '회원';
      if (recentPatternCount < kPatternMinLogs) {
        await cancelPatternReminders();
        await clearPatternReminderSlots();
        unawaited(_syncPatternLogToApi(log));
        return;
      }

      final slots = buildPatternAverageSlots(list);
      await schedulePatternRemindersFromSlots(
        slots: slots,
        nickname: nickname,
      );
      unawaited(_syncPatternLogToApi(log));
    } catch (e, st) {
      // 로컬 로그는 이미 저장된 상태. 알림 예약만 실패한 경우가 많음 → 사용자 화면은 저장 성공만 안내.
      if (kDebugMode) {
        debugPrint(
          '패턴 알림 예약 단계 오류(로컬 기록은 이미 저장됨): $e\n$st',
        );
      }
      unawaited(_syncPatternLogToApi(log));
    }
  }

  Future<void> _syncPatternLogToApi(_SmokingPatternLog log) async {
    if (!SupabaseConfig.isConfigured) return;
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token == null || token.isEmpty) return;
    try {
      await _smokingPatternApi.postLog(
        accessToken: token,
        action: log.action,
        eventAtMs: log.tsMs,
        hour: log.hour,
        minute: log.minute,
        timeLabel: log.timeLabel,
        situation: log.situation,
        emotion: log.emotion,
      );
    } catch (_) {}
  }

  Future<bool> _showSmokingReasonDialog({required String action}) async {
    final result = await SmokingRecordSheet.show(context: context, action: action);
    if (result == null) return false;
    final timeValue = result['time'] as String;
    final situationValue = result['situation'] as String;
    final emotionValue = result['emotion'] as String;
    final now = DateTime.now();
    final log = _SmokingPatternLog(
      id: now.millisecondsSinceEpoch,
      action: action,
      hour: now.hour,
      minute: now.minute,
      timeLabel: timeValue,
      situation: situationValue,
      emotion: emotionValue,
      tsMs: now.millisecondsSinceEpoch,
    );
    try {
      await _savePatternAndSchedule(log);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('방금 피움 저장 실패: $e\n$st');
      }
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('저장하지 못했어요'),
          content: const Text(
            '기록 저장 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return false;
    }
    if (!mounted) return false;
    return true;
  }

  /// 저장 완료 피드백은 오버레이 다이얼로그로 표시한다.
  Future<void> _showCravingSavedFeedback() async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('욕구 기록이 저장되었습니다'),
        content: Text(
          '욕구가 올라온 시간을 기록했어요.\n패턴 알림 분석에 반영됩니다.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// 저장 완료 피드백 — [runSmokingRecordFlow]에서 처리
  Future<void> _onSmokedTap() async {
    final ok = await runSmokingRecordFlow(
      context,
      showReasonSheet: (ctx, {required action}) =>
          SmokingRecordSheet.show(context: ctx, action: action),
    );
    if (!ok || !mounted) return;
    await _reloadAfterSmokingRecord();
  }

  Future<void> _reloadAfterSmokingRecord() async {
    final prefs = await SharedPreferences.getInstance();
    _failureCount = prefs.getInt(_failureCountKey) ?? 0;
    final millis = prefs.getInt('startTime');
    if (millis != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(millis);
    }
    _refreshQuitMetricsDisplay();
    if (mounted) setState(() {});
  }

  Future<void> _openQuitModeSettings() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const QuitModeSettingsScreen()),
    );
    if (changed == true && mounted) {
      _quitMode = await QuitModePrefs.getMode();
      setState(() {});
    }
  }

  Future<void> _onStrongCravingTap() async {
    final saved = await _showSmokingReasonDialog(action: 'craving');
    if (!saved) return;
    await _showCravingSavedFeedback();
  }

  Future<void> _onSosTap() async {
    if (!mounted) return;
    await SosOverlay.show(
      context,
      reason: _mainReason.isNotEmpty ? _mainReason : null,
      onDone: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('3분 미션 완료! 잘 버텨냈어요 💪')),
          );
        }
      },
      onSmoked: _onSmokedTap,
    );
  }

  String _shareDaysLabel(int days) {
    if (_quitMode == QuitMode.restart) {
      return '$days일째 (이번 시도)';
    }
    return '$days일째';
  }

  Future<void> _shareTodayRecord() async {
    final days = _startTime != null ? quitCalendarDayNumber(_startTime!) : 0;
    final savedStr = _moneyFormatter.format(_savedMoney.round());
    final cigsStr = _skippedCigarettes;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy년 MM월 dd일').format(now);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 20, 24,
          24 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '오늘의 기록 공유하기',
              style: Theme.of(ctx).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '$dateStr · ${_shareDaysLabel(days)} 금연 중',
              style: Theme.of(ctx).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _ShareOptionTile(
              icon: Icons.chat_bubble_rounded,
              color: const Color(0xFFFAE100),
              iconColor: const Color(0xFF3A1D00),
              title: '카카오톡으로 공유',
              subtitle: '지인에게 금연 현황을 전달해요',
              onTap: () {
                Navigator.pop(ctx);
                _shareToKakao(days, savedStr, cigsStr);
              },
            ),
            const SizedBox(height: 10),
            _ShareOptionTile(
              icon: Icons.people_rounded,
              color: AppTheme.primary,
              iconColor: Colors.white,
              title: '금연방에 공유',
              subtitle: '파트너들에게 오늘 기록을 알려요',
              onTap: () {
                Navigator.pop(ctx);
                _shareToQuitRoom(days, savedStr, cigsStr);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareToKakao(int days, String savedStr, int cigsStr) async {
    final label = _shareDaysLabel(days);
    final text = '[$label 금연 중이에요 🌱]\n\n'
        '오늘도 담배를 참았어요!\n'
        '지금까지 ₩$savedStr 절약, 담배 $cigsStr개비를 넘겼어요.\n\n'
        '금연뱅크와 함께해요!\n'
        'Android: $_kAppPlayStoreUrl';
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('공유 화면을 열 수 없습니다.')));
    }
  }

  Future<void> _shareToQuitRoom(int days, String savedStr, int cigsStr) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = decodeRooms(prefs.getString(kQuitRoomsKey));
    if (rooms.isEmpty) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('금연방이 없어요'),
          content: const Text('금연방을 개설하면 파트너와 함께 기록을 나눌 수 있어요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('금연방 열기')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const QuitRoomListScreen()),
        );
      }
      return;
    }

    final targetRoom = await QuitRoomPostService.pickRoom(context, rooms);
    if (targetRoom == null || !mounted) return;

    final stats = await QuitRoomStatsLoader.loadFromPrefs();
    final postContent =
        '${_shareDaysLabel(days)} · ₩$savedStr · $cigsStr개비 참았어요!';

    final result = await QuitRoomPostService.shareStatsToRoom(
      context: context,
      room: targetRoom,
      stats: stats,
      message: postContent,
    );

    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「${targetRoom.name}」에 공유했어요!')),
    );
  }

  /// 금연 시간을 년/월/일/시간/분/초로 표시
  String formatDurationLong(Duration d) {
    final dur = d.isNegative ? Duration.zero : d;
    final totalDays = dur.inDays;
    final years = totalDays ~/ 365;
    final remainderDays = totalDays % 365;
    final months = remainderDays ~/ 30;
    final days = remainderDays % 30;
    final hours = dur.inHours.remainder(24);
    final minutes = dur.inMinutes.remainder(60);
    final seconds = dur.inSeconds.remainder(60);
    final parts = <String>[];
    if (years > 0) parts.add('${years}년');
    if (months > 0) parts.add('${months}개월');
    if (days > 0 || parts.isNotEmpty) parts.add('${days}일');
    parts.add('${hours}시간');
    parts.add('${minutes}분');
    parts.add('${seconds}초');
    return parts.join(' ');
  }

  Future<void> _openHabitSettings() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const HabitSettingsScreen()),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정값을 저장했습니다.')),
      );
      await Future.delayed(const Duration(milliseconds: 250));
      relaunchAppRoot();
    }
  }

  Future<void> _performFullReset() async {
    await AppAnalytics.log('full_reset_from_settings', params: {'source': 'settings'});

    try {
      await disableDailyReminder();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reminderHour');
    await prefs.remove('reminderMinute');

    // 로컬만 즉시 초기화 (네트워크 hang 없음)
    await SupabaseSyncService.resetOnboardingForIntroReplay();

    if (kDebugMode) {
      final p = await SharedPreferences.getInstance();
      debugPrint(
        '_performFullReset done: '
        'force=${p.getBool('supabase_force_onboarding_once')} '
        'configured=${p.getBool('isConfigured')}',
      );
    }

    // 설정 화면 등 스택을 비우고 intro로 재진입
    relaunchAppRoot();
  }


  @override
  Widget build(BuildContext context) {
    final formattedStart =
        _startTime != null ? DateFormat('yyyy년 MM월 dd일').format(_startTime!) : '';
    final days = _startTime != null ? quitCalendarDayNumber(_startTime!) : 0;
    final savedMoneyStr = _moneyFormatter.format(_savedMoney.round());
    final goalProgress = _goalDays != null && _goalDays! > 0
        ? (days / _goalDays!).clamp(0.0, 1.0)
        : null;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/app_icon.png', width: 28, height: 28, fit: BoxFit.cover),
            ),
            const SizedBox(width: 8),
            const Text('홈'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: '오늘의 기록 공유',
            onPressed: _shareTodayRecord,
          ),
          Builder(
            builder: (innerCtx) {
              return IconButton(
                icon: const Icon(Icons.settings_rounded),
                tooltip: '설정',
                onPressed: () async {
                  await Navigator.push<void>(
                    innerCtx,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        reminderTimes: List.from(_reminderTimes),
                        onReminderUpdated: (list) =>
                            setState(() => _reminderTimes = list),
                        onEditHabits: _openHabitSettings,
                        onFullReset: _performFullReset,
                        onShowTutorial: widget.onShowTutorial,
                      ),
                    ),
                  );
                  await _reloadReminderTimesFromPrefs();
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: widget.mainScrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(
              builder: (context) {
                final hero = HomeHeroCard(
                  days: days,
                  durationLabel: formatDurationLong(_elapsed),
                  startLabel: formattedStart.isEmpty ? '' : '시작 $formattedStart',
                  savedMoneyLabel: savedMoneyStr,
                  skippedCigarettes: _skippedCigarettes,
                  goalDays: _goalDays,
                  goalProgress: goalProgress,
                  failureCount: _failureCount,
                  reasonText: _mainReason.isEmpty ? null : _mainReason,
                  quitMode: _quitMode,
                  onModeTap: _openQuitModeSettings,
                  onGoalTap: _pickGoalDays,
                  onReasonTap: _openReasonEditorInline,
                );
                final tk = widget.tutorialStatsCardKey;
                if (tk != null) return KeyedSubtree(key: tk, child: hero);
                return hero;
              },
            ),
            FutureSavingsSection(
              dailyCigarettes: widget.dailyCigarettes,
              cigarettesPerPack: widget.cigarettesPerPack,
              pricePerPack: widget.pricePerPack,
            ),
            if (_showReasonEditor)
              AppCard(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      icon: Icons.edit_note_rounded,
                      title: '금연할 이유 적기',
                      subtitle: '힘든 순간, 이 한 줄이 버티게 해줘요.',
                      iconColor: AppTheme.primary,
                      iconBackground: AppTheme.primarySurface,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reasonController,
                      focusNode: _reasonFocusNode,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 120,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '예) 아이와 더 오래 건강하게 살고 싶어요',
                      ),
                      onSubmitted: (_) => _saveMainReasonFromInput(),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saveMainReasonFromInput,
                        child: const Text('저장하기'),
                      ),
                    ),
                  ],
                ),
              ),
            // ─── 응급 SOS ────────────────────────────────────
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final sos = _SosButton(onTap: _onSosTap);
                final sk = widget.tutorialSosButtonKey;
                if (sk != null) return KeyedSubtree(key: sk, child: sos);
                return sos;
              },
            ),
            const SizedBox(height: 20),

            // ─── 오늘의 기록 공유하기 ─────────────────────
            AppCard(
              padding: const EdgeInsets.all(16),
              onTap: _shareTodayRecord,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.ios_share_rounded, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('오늘의 기록 공유하기', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '카카오톡 또는 금연방에 공유',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.border, size: 16),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── 오늘 기록하기 ───────────────────────────
            const SectionHeader(
              icon: Icons.fact_check_outlined,
              title: '오늘 기록하기',
              subtitle: '패턴을 남기면 레포트와 알림이 맞춰져요.',
              iconColor: AppTheme.primary,
              iconBackground: AppTheme.primarySurface,
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final recordSection = Row(
                  children: [
                    Expanded(
                      child: _RecordTypeButton(
                        icon: Icons.smoking_rooms_rounded,
                        label: '흡연했어요',
                        description: '상황 기록',
                        color: AppTheme.error,
                        bgColor: const Color(0xFFFEE2E2),
                        onTap: _onSmokedTap,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RecordTypeButton(
                        icon: Icons.whatshot_rounded,
                        label: '욕구가 올라요',
                        description: '참은 순간 기록',
                        color: AppTheme.craving,
                        bgColor: const Color(0xFFFFEDD5),
                        onTap: _onStrongCravingTap,
                      ),
                    ),
                  ],
                );
                final sk = widget.tutorialSmokedButtonKey;
                if (sk != null) return KeyedSubtree(key: sk, child: recordSection);
                return recordSection;
              },
            ),
            const SizedBox(height: 18),
            Builder(
              builder: (_) {
                final reminderBtn = ActionListTile(
                  icon: Icons.notifications_none_rounded,
                  title: _reminderTimes.isEmpty ? '알림 맞추기' : '알림 ${_reminderTimes.length}개 켜짐',
                  subtitle: '피우고 싶을 때를 미리 챙겨두세요',
                  iconColor: AppTheme.primary,
                  iconBackground: AppTheme.primarySurface,
                  onTap: _openReminderSettings,
                );
                final rk = widget.tutorialReminderButtonKey;
                if (rk != null) return KeyedSubtree(key: rk, child: reminderBtn);
                return reminderBtn;
              },
            ),
            if (_isBannerReady && _bannerAd != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 기록 타입 버튼 ───────────────────────────────────────────────────
class _RecordTypeButton extends StatelessWidget {
  const _RecordTypeButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 응급 SOS 버튼 ────────────────────────────────────────────────────
class _SosButton extends StatelessWidget {
  const _SosButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB91C1C), Color(0xFFE53E3E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB91C1C).withValues(alpha: 0.35),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '못참겠어요',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '지금 당장 피우고 싶다면 눌러요',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '3분 미션',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.7),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 공유 선택지 타일 ─────────────────────────────────────────────────
class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}