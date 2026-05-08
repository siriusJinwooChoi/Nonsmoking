import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ SystemNavigator.pop
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/remote_assets.dart';
import '../api/bff_profile_api.dart';
import '../auth/bff_auth_service.dart';

import '../data/savings_coin_exchange.dart';
import 'reason_why_screen.dart';
import 'nonsmoke_helper_screen.dart';
import 'reminder_settings_screen.dart';
import 'savings_coin_exchange_screen.dart';
import 'settings_screen.dart';
import 'attendance_screen.dart';
import 'smoking_screen.dart';
import '../theme/app_theme.dart';
import '../ad_unit_ids.dart';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

// ✅ WorkManager 알림(네 프로젝트 구조 기준)
import '../notifications/daily_reminder_worker.dart';
// ✅ 홈 화면 위젯 갱신(동기화)
import '../widget/widget_helper.dart';
import '../supabase/supabase_config.dart';
import '../api/reasons_api_service.dart';
import '../api/smoking_pattern_api_service.dart';

class MainScreen extends StatefulWidget {
  final VoidCallback onAlarmTap;
  final VoidCallback onCravingTap;
  final VoidCallback onResetTap;
  final VoidCallback onReasonTap;
  final VoidCallback onHelperTap;
  final int? refreshTrigger;

  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;

  const MainScreen({
    super.key,
    required this.onAlarmTap,
    required this.onCravingTap,
    required this.onResetTap,
    required this.onReasonTap,
    required this.onHelperTap,
    this.refreshTrigger,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
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
  int _goldenCoins = 0;
  /// 절약 금액 중 코인으로 이미 바꾼 누적 원화(메인·환전 화면 동기화).
  int _savingsExchangedToCoinsWon = 0;
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
  String? _lastPatternSummaryText;

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
      _loadGoldenCoins();
      unawaited(_reloadSavingsExchangePrefs());
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
  static const String _smokingPatternLogsKey = 'smoking_pattern_logs_v1';
  static const int _patternWindowDays = 30;
  static const int _patternMinLogs = 5;
  static const int _patternBinMinutes = 30;
  static const int _patternMaxSlots = 5;
  static const int _patternMergeBins = 2; // 30분 bin 기준 ±2칸(약 1시간) 이내는 같은 피크로 본다.

  Future<void> _reloadSavingsExchangePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _savingsExchangedToCoinsWon =
          prefs.getInt(kSavingsExchangedToCoinsWonKey) ?? 0;
    });
  }

  Future<void> _openSavingsCoinExchange() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SavingsCoinExchangeScreen(
          dailyCigarettes: widget.dailyCigarettes,
          cigarettesPerPack: widget.cigarettesPerPack,
          pricePerPack: widget.pricePerPack,
        ),
      ),
    );
    await _loadGoldenCoins();
    await _reloadSavingsExchangePrefs();
    if (mounted) setState(() {});
  }

  int get _totalSavedWon => _savedMoney.floor().clamp(0, 0x7fffffff);

  int get _exchangeableWon =>
      (_totalSavedWon - _savingsExchangedToCoinsWon).clamp(0, 0x7fffffff);

  Future<void> _loadGoldenCoins() async {
    final coins = await getGoldenCoins();
    if (mounted) setState(() => _goldenCoins = coins);
  }

  /// prefs 기준으로 알림 개수 라벨 동기화 (설정 화면 pop 직후·다른 탭 복귀 등)
  Future<void> _reloadReminderTimesFromPrefs() async {
    final fresh = await getReminderTimes();
    if (!mounted) return;
    setState(() => _reminderTimes = fresh);
  }

  /// 실패 횟수 1회 차감 (금연코인 5개 소모) 다이얼로그
  Future<void> _showReduceFailureCountDialog() async {
    final ctx = context;
    final coins = await getGoldenCoins();
    final canReduce = coins >= 5 && _failureCount > 0;
    if (!ctx.mounted) return;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('실패 횟수 차감'),
        content: Text(
          canReduce
              ? '금연코인 5개를 사용하여 실패 횟수를 1개 차감하시겠습니까?'
              : '금연코인이 부족합니다. (5코인 필요)\n현재 보유: $coins코인',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          if (canReduce)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('확인'),
            ),
        ],
      ),
    );
    if (confirmed != true || !canReduce) return;
    final remaining = await consumeCoinsIfPossible(5);
    if (remaining == null) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('금연코인이 부족합니다. (5코인 필요)')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _failureCount = (_failureCount - 1).clamp(0, 0x7fffffff);
    await prefs.setInt(_failureCountKey, _failureCount);
    await _loadGoldenCoins();
    if (!ctx.mounted) return;
    setState(() {});
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final millis = prefs.getInt('startTime');
    _failureCount = prefs.getInt(_failureCountKey) ?? 0;
    _goldenCoins = prefs.getInt(kGoldenCoinsKey) ?? 0;
    _savingsExchangedToCoinsWon =
        prefs.getInt(kSavingsExchangedToCoinsWonKey) ?? 0;
    _mainReason = prefs.getString('pinnedReasonText') ?? '';
    _reasonController.text = _mainReason;
    _showReasonEditor = _mainReason.isEmpty;
    final savedGoal = prefs.getInt(kGoalDaysKey);
    _goalDays = savedGoal != null && savedGoal > 0 ? savedGoal : null;

    // 로컬 우선 표시 후, 로그인 상태면 서버 값으로 동기화(느려도 UI 블로킹 없음)
    unawaited(_syncMainReasonFromApiIfAvailable());

    if (millis != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(millis);
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

      // 목표일 도달 시 축하 알림 (한 번만)
      final days = diff.inDays;
      if (_goalDays != null && days >= _goalDays!) {
        showGoalReachedNotificationIfNeeded(days, _goalDays);
      }

      // 위젯 데이터도 주기적으로 동기화 (대략 1분마다)
      if (seconds % 60 == 0) {
        syncWidgetData();
      }
    });
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
                for (final d in [7, 14, 30, 60, 90, 365])
                  ListTile(
                    title: Text('$d일'),
                    onTap: () => Navigator.pop(ctx, d),
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

  /// 흡연 욕구 시 금연시간, 절약금액, 별표(고정)한 금연할 이유, 응원메시지 표시
  Future<void> _showCravingSheet() async {
    final prefs = await SharedPreferences.getInstance();
    final reasonText = prefs.getString('pinnedReasonText');
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).padding.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('마음이 흔들릴 때', style: AppTheme.titleLarge),
                const SizedBox(height: 20),
                _cravingRow(Icons.timer_outlined, '금연 시간', formatDurationLong(_elapsed)),
                const SizedBox(height: 12),
                _cravingRow(Icons.savings_outlined, '절약 금액', '₩${_moneyFormatter.format(_savedMoney.round())}'),
                if (reasonText != null && reasonText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _cravingRow(Icons.format_quote_rounded, '금연할 이유', reasonText),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '지금까지 $_skippedCigarettes개비를 넘기셨어요! 조금만 더 힘내세요.',
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('금연 스트레스 완화 영상', style: AppTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        '아래 버튼을 누르면 유튜브에서 관련 영상 목록을 바로 볼 수 있어요.',
                        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('금연 스트레스 완화'),
                            onPressed: () => _openExternalYoutubeSearch('금연 스트레스 완화'),
                          ),
                          ActionChip(
                            label: const Text('금연 불안 호흡'),
                            onPressed: () => _openExternalYoutubeSearch('금연 불안 호흡 명상'),
                          ),
                          ActionChip(
                            label: const Text('욕구 이겨내기'),
                            onPressed: () => _openExternalYoutubeSearch('금연 욕구 이겨내기'),
                          ),
                          ActionChip(
                            label: const Text('금연하는 방법'),
                            onPressed: () => _openExternalYoutubeSearch('금연하는 방법'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _cravingRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 22),
        const SizedBox(width: 10),
        Text('$label: ', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
        Expanded(child: Text(value, style: AppTheme.titleMedium)),
      ],
    );
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

  Future<void> _openExternalYoutubeSearch(String keyword) async {
    final url = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(keyword)}';
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유튜브를 열 수 없습니다.')),
      );
    }
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

  List<Map<String, dynamic>> _decodePatternLogs(String? raw) {
    final list = <Map<String, dynamic>>[];
    if (raw == null || raw.isEmpty) return list;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded.whereType<Map>()) {
          list.add(Map<String, dynamic>.from(item));
        }
      }
    } catch (_) {}
    return list;
  }

  List<TimeOfDay> _buildPatternPeakSlots(List<Map<String, dynamic>> logs) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowMs = _patternWindowDays * 24 * 60 * 60 * 1000;
    final binsPerDay = (24 * 60) ~/ _patternBinMinutes; // 48
    final scores = List<double>.filled(binsPerDay, 0.0);

    for (final e in logs) {
      final action = (e['action'] as String?) ?? '';
      if (action != 'smoked') continue;
      final tsMs = (e['tsMs'] as num?)?.toInt();
      final hour = (e['hour'] as num?)?.toInt();
      final minute = (e['minute'] as num?)?.toInt();
      if (tsMs == null || hour == null || minute == null) continue;
      final ageMs = nowMs - tsMs;
      if (ageMs < 0 || ageMs > windowMs) continue;
      final ageDays = ageMs / (24 * 60 * 60 * 1000);
      // 최근 데이터에 더 큰 가중치: 14일 반감 느낌의 지수 감쇠
      final weight = 1.0 / (1.0 + (ageDays / 14.0));
      final minuteOfDay = hour * 60 + minute;
      final bin = (minuteOfDay ~/ _patternBinMinutes).clamp(0, binsPerDay - 1);
      scores[bin] += weight;
    }

    final totalScore = scores.fold<double>(0.0, (a, b) => a + b);
    if (totalScore <= 0) return const <TimeOfDay>[];

    final ranked = List<int>.generate(binsPerDay, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final topScore = scores[ranked.first];
    if (topScore <= 0) return const <TimeOfDay>[];

    final selectedBins = <int>[];
    double selectedScore = 0.0;
    for (final bin in ranked) {
      if (selectedBins.length >= _patternMaxSlots) break;
      final score = scores[bin];
      if (score <= 0) break;
      final tooClose = selectedBins.any((picked) => (picked - bin).abs() <= _patternMergeBins);
      if (tooClose) continue;
      if (selectedBins.isEmpty) {
        selectedBins.add(bin);
        selectedScore += score;
        continue;
      }
      final strongEnough = score >= topScore * 0.45;
      final coverage = selectedScore / totalScore;
      // 기본 1개에서 시작, 강한 피크가 남아 있고 전체 커버리지가 낮을 때만 1개씩 증가
      if (strongEnough && coverage < 0.80) {
        selectedBins.add(bin);
        selectedScore += score;
      }
    }

    selectedBins.sort();
    return selectedBins.map((bin) {
      final minuteOfDay = bin * _patternBinMinutes;
      final h = minuteOfDay ~/ 60;
      final m = minuteOfDay % 60;
      return TimeOfDay(hour: h, minute: m);
    }).toList();
  }

  String _formatPatternSlots(List<TimeOfDay> slots) {
    if (slots.isEmpty) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return slots.map((s) => '${two(s.hour)}:${two(s.minute)}').join(', ');
  }

  Future<String> _savePatternAndSchedule(_SmokingPatternLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_smokingPatternLogsKey);
    final list = _decodePatternLogs(raw);
    list.add(log.toJson());
    if (list.length > 200) {
      list.removeRange(0, list.length - 200);
    }
    await prefs.setString(_smokingPatternLogsKey, jsonEncode(list));

    final recentSmokedCount = list.where((e) {
      final action = (e['action'] as String?) ?? '';
      if (action != 'smoked') return false;
      final ts = (e['tsMs'] as num?)?.toInt();
      if (ts == null) return false;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      return age >= 0 && age <= _patternWindowDays * 24 * 60 * 60 * 1000;
    }).length;

    final nickname = await _resolveNicknameForPatternNotification() ?? '회원';
    if (recentSmokedCount < _patternMinLogs) {
      await cancelPatternReminders();
      await clearPatternReminderSlots();
      unawaited(_syncPatternLogToApi(log));
      return '패턴 데이터가 아직 부족해요 ($recentSmokedCount/$_patternMinLogs건).\n'
          '기록이 $_patternMinLogs건 이상 쌓이면 자동으로 피크 시간대를 계산해 알림을 시작합니다.';
    }

    final slots = _buildPatternPeakSlots(list);
    await schedulePatternRemindersFromSlots(
      slots: slots,
      nickname: nickname,
    );
    unawaited(_syncPatternLogToApi(log));
    final slotText = _formatPatternSlots(slots);
    return '최근 $_patternWindowDays일 기록을 30분 단위로 분석해 '
        '${slots.length}개 피크 시간대를 설정했어요.\n'
        '예방 알림 시간: $slotText (각 시간 3분 전 발송)\n'
        '설정 > 알림 해지에서 언제든 해지할 수 있어요.';
  }

  Future<void> _savePatternLogOnly(_SmokingPatternLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_smokingPatternLogsKey);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            list.add(Map<String, dynamic>.from(item));
          }
        }
      } catch (_) {}
    }
    list.add(log.toJson());
    if (list.length > 200) {
      list.removeRange(0, list.length - 200);
    }
    await prefs.setString(_smokingPatternLogsKey, jsonEncode(list));
    unawaited(_syncPatternLogToApi(log));
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
    String timeValue = '아침';
    String situationValue = '스트레스';
    String emotionValue = '짜증';
    final situationEtcController = TextEditingController();
    final emotionEtcController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(action == 'smoked' ? '방금 피움 이유 기록' : '강한 욕구 기록'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: timeValue,
                  decoration: const InputDecoration(labelText: '시간대'),
                  items: const [
                    DropdownMenuItem(value: '아침', child: Text('아침')),
                    DropdownMenuItem(value: '식사 전후', child: Text('식사 전후')),
                    DropdownMenuItem(value: '밤', child: Text('밤')),
                  ],
                  onChanged: (v) => setDialogState(() => timeValue = v ?? '아침'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: situationValue,
                  decoration: const InputDecoration(labelText: '상황'),
                  items: const [
                    DropdownMenuItem(value: '스트레스', child: Text('스트레스')),
                    DropdownMenuItem(value: '심심함', child: Text('심심함')),
                    DropdownMenuItem(value: '술자리', child: Text('술자리')),
                    DropdownMenuItem(value: '습관', child: Text('습관')),
                    DropdownMenuItem(value: '기타', child: Text('기타(직접입력)')),
                  ],
                  onChanged: (v) => setDialogState(() => situationValue = v ?? '스트레스'),
                ),
                if (situationValue == '기타') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: situationEtcController,
                    decoration: const InputDecoration(hintText: '상황 입력'),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: emotionValue,
                  decoration: const InputDecoration(labelText: '감정'),
                  items: const [
                    DropdownMenuItem(value: '짜증', child: Text('짜증')),
                    DropdownMenuItem(value: '피곤', child: Text('피곤')),
                    DropdownMenuItem(value: '집중 안됨', child: Text('집중 안됨')),
                    DropdownMenuItem(value: '기타', child: Text('기타(직접입력)')),
                  ],
                  onChanged: (v) => setDialogState(() => emotionValue = v ?? '짜증'),
                ),
                if (emotionValue == '기타') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: emotionEtcController,
                    decoration: const InputDecoration(hintText: '감정 입력'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return false;
    final now = DateTime.now();
    final log = _SmokingPatternLog(
      id: now.millisecondsSinceEpoch,
      action: action,
      hour: now.hour,
      minute: now.minute,
      timeLabel: timeValue,
      situation: situationValue == '기타'
          ? (situationEtcController.text.trim().isEmpty
              ? '기타'
              : situationEtcController.text.trim())
          : situationValue,
      emotion: emotionValue == '기타'
          ? (emotionEtcController.text.trim().isEmpty
              ? '기타'
              : emotionEtcController.text.trim())
          : emotionValue,
      tsMs: now.millisecondsSinceEpoch,
    );
    final summaryText = await _savePatternAndSchedule(log);
    _lastPatternSummaryText = summaryText;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기록을 저장했습니다.')),
    );
    return true;
  }

  Future<void> _onSmokedTap() async {
    final saved = await _showSmokingReasonDialog(action: 'smoked');
    if (!saved) return;
    final prefs = await SharedPreferences.getInstance();
    _failureCount = (prefs.getInt(_failureCountKey) ?? 0) + 1;
    await prefs.setInt(_failureCountKey, _failureCount);
    final before = prefs.getInt('lungHealth') ?? 100;
    final after = (before - 10).clamp(0, 100);
    await prefs.setInt('lungHealth', after);
    await syncWidgetData();
    if (!mounted) return;
    setState(() {});
    final summary = _lastPatternSummaryText ??
        '기록을 저장했습니다. 다음날부터 패턴 기반 예방 알림을 보내드릴게요.\n'
            '설정 > 알림 해지에서 패턴 기반 자동 알림 기능을 해지할 수 있어요.';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('패턴 저장 완료'),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _onStrongCravingTap() async {
    final now = DateTime.now();
    await _savePatternLogOnly(
      _SmokingPatternLog(
        id: now.millisecondsSinceEpoch,
        action: 'craving',
        hour: now.hour,
        minute: now.minute,
        timeLabel: '',
        situation: '',
        emotion: '',
        tsMs: now.millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SmokingScreen()),
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

  Future<void> _resetSmokingStatus() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('⚠️ 금연 리셋'),
          content: const Text('정말로 금연 리셋을 진행하시겠습니까?\n기록이 초기화됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setInt('startTime', now.millisecondsSinceEpoch);
    setState(() => _startTime = now);
    _refreshQuitMetricsDisplay();
    await syncWidgetData();

    // (기존 로직 유지: 폐 건강 -10)
    final before = prefs.getInt('lungHealth') ?? 100;
    final after = (before - 10).clamp(0, 100);
    await prefs.setInt('lungHealth', after);

    // ✅ Analytics
    await AppAnalytics.log('reset_quit', params: {
      'lung_before': before,
      'lung_after': after,
      'source': 'main_screen',
    });

    widget.onResetTap();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('금연 리셋이 완료되었습니다.')),
      );
    }
  }

  // ✅ 설정 아이콘: "처음 설정으로 돌아가기" 구현
  Future<void> _confirmAndGoToFirstSetup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('처음 설정으로 돌아가기'),
        content: const Text(
          '처음 설정 화면으로 돌아가시겠습니까?\n\n'
              '⚠️ 입력한 설정(흡연량/가격 등)과 진행 기록이 초기화될 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // ✅ Analytics
    await AppAnalytics.log('go_to_first_setup', params: {'source': 'main_screen'});

    // ✅ 알림 OFF(예약 작업 취소 + 설정 제거)
    await disableDailyReminder();

    // ✅ 설정값 초기화 (필요 키만 삭제해도 되지만, 안전하게 관련 키 정리)
    final prefs = await SharedPreferences.getInstance();

    // "처음 설정"에 영향을 주는 값들
    await prefs.setBool('isConfigured', false);
    await prefs.remove('dailyCigarettes');
    await prefs.remove('cigarettesPerPack');
    await prefs.remove('pricePerPack');

    // 시작시간/리마인더 관련
    await prefs.remove('startTime');
    await prefs.remove('reminderHour');
    await prefs.remove('reminderMinute');

    // (선택) 광고 클릭 카운트도 초기화하고 싶으면
    // await prefs.remove('clickCount');

    // (선택) 나무/게임/폐 건강 등도 "처음부터"로 돌리고 싶으면 같이 초기화
    // await prefs.remove('growthStage');
    // await prefs.remove('water');
    // await prefs.remove('currentWater');
    // await prefs.remove('bestRecord');
    // await prefs.remove('lungHealth');
    // await prefs.remove('lastUpdatedTime');
    // await prefs.remove('lastExitTime');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('초기 설정으로 돌아갑니다. 앱을 다시 시작합니다.')),
      );
    }

    // ✅ 현재 구조에서 가장 안전한 방식: 앱 종료 후 재실행
    // (재실행하면 isConfigured=false라 IntroFlowWrapper가 다시 뜸)
    await Future.delayed(const Duration(milliseconds: 400));
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final formattedStart =
    _startTime != null ? DateFormat('yyyy년 MM월 dd일').format(_startTime!) : '';
    final days = _startTime != null ? DateTime.now().difference(_startTime!).inDays : 0;
    final savedMoneyStr = _moneyFormatter.format(_savedMoney.round());
    final exchangeableStr = _moneyFormatter.format(_exchangeableWon);
    final appBarFg =
        Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 0,
        // 좌·우 영역을 동일한 Expanded로 잡아야 「금연 현황」이 화면 기준으로 정확히 중앙에 온다.
        title: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openSavingsCoinExchange,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '금연코인',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  color: appBarFg,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            RemoteAssetImage(
                              assetKey: 'scoin.png',
                              width: 22,
                              height: 22,
                              memCacheWidth: 64,
                              error: Icon(
                                Icons.monetization_on_rounded,
                                color: appBarFg.withValues(alpha: 0.95),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_goldenCoins',
                              style: TextStyle(
                                color: appBarFg,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                '금연 현황',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appBarFg,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: '설정',
                    color: appBarFg,
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                            reminderTimes: List.from(_reminderTimes),
                            onReminderUpdated: (list) =>
                                setState(() => _reminderTimes = list),
                            onGoToFirstSetup: _confirmAndGoToFirstSetup,
                          ),
                        ),
                      );
                      await _reloadReminderTimesFromPrefs();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 금연 시간 위젯 (한눈에 보이는 영역)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppTheme.cardShadowSubtle,
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.timer_outlined, color: AppTheme.primary, size: 24),
                  const SizedBox(width: 10),
                  Text('금연 시간', style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatDurationLong(_elapsed),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.titleLarge.copyWith(
                        color: AppTheme.primary,
                        fontSize: 13,
                        height: 1.25,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openReasonEditorInline,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppTheme.cardShadowSubtle,
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15), width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _mainReason.isEmpty
                              ? '금연할 이유: 아직 입력된 이유가 없습니다.'
                              : '금연할 이유: $_mainReason',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(Icons.edit_rounded, size: 20, color: AppTheme.primary),
                        tooltip: '이유 편집',
                        onPressed: _openReasonEditorInline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 상단 요약 카드
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryLight, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('시작일', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                      Text(formattedStart, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('누적일', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                      Text('$days일', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickGoalDays,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('목표일', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _goalDays != null ? '$_goalDays일' : '설정',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.touch_app_rounded, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('참은 담배 개수', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13)),
                      Text('$_skippedCigarettes개비', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(height: 1, color: Colors.white24),
                  const SizedBox(height: 22),
                  Text(
                    formatDurationLong(_elapsed),
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.25, fontWeight: FontWeight.w700),
                  ),
                  if (_failureCount > 0) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _showReduceFailureCountDialog,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '실패 $_failureCount회',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.touch_app_rounded, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('총 절약 금액', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                              Text('₩$savedMoneyStr', style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openSavingsCoinExchange,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '환전 가능 금액',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.touch_app_rounded,
                                        size: 12,
                                        color: Colors.white.withValues(alpha: 0.65),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₩$exchangeableStr',
                                    style: TextStyle(
                                      color: Colors.lightGreenAccent.shade100,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_showReasonEditor)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppTheme.cardShadowSubtle,
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.format_quote_rounded, color: AppTheme.primary, size: 22),
                        const SizedBox(width: 8),
                        Text('금연할 이유', style: AppTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '힘든 순간에 떠올릴 한 문장을 적어두세요.',
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonController,
                      focusNode: _reasonFocusNode,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 120,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '예) 가족과 더 건강하게 오래 살고 싶어요.',
                      ),
                      onSubmitted: (_) => _saveMainReasonFromInput(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveMainReasonFromInput,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('이유 저장'),
                      ),
                    ),
                  ],
                ),
              ),

            // 알림 / 마음 다잡기
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openReminderSettings,
                    icon: const Icon(Icons.notifications_active_rounded, size: 20),
                    label: Text(_reminderTimes.isEmpty ? '알림 설정' : '알림 ${_reminderTimes.length}개'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showCravingSheet,
                    icon: const Icon(Icons.self_improvement_rounded, size: 20),
                    label: const Text('마음 다잡기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 금연할 이유 / 금연 도우미
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                    label: const Text('금연할 이유'),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReasonWhyScreen()));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.warning,
                      side: const BorderSide(color: AppTheme.warning),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.volunteer_activism_rounded, size: 20),
                    label: const Text('금연 도우미'),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NonsmokeHelperScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 방금 피움 / 지금 너무 피우고 싶을때
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onSmokedTap,
                    icon: const Icon(Icons.waves_rounded, size: 16),
                    label: const Text('방금 피움', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _onStrongCravingTap,
                    icon: const Icon(Icons.local_fire_department_rounded, size: 16),
                    label: const Text('지금 너무 피우고싶을때', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warning,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

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