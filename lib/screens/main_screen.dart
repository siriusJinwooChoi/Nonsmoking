import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ SystemNavigator.pop
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'reason_why_screen.dart';
import 'nonsmoke_helper_screen.dart';
import 'reminder_settings_screen.dart';
import 'settings_screen.dart';
import 'attendance_screen.dart';
import '../theme/app_theme.dart';
import '../ad_manager.dart';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

// ✅ WorkManager 알림(네 프로젝트 구조 기준)
import '../notifications/daily_reminder_worker.dart';
// ✅ 홈 화면 위젯 갱신(동기화)
import '../widget/widget_helper.dart';

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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  double _savedMoney = 0;
  int _skippedCigarettes = 0;
  int _failureCount = 0;
  int? _goalDays;
  int _goldenCoins = 0;
  Timer? _timer;
  List<TimeOfDay> _reminderTimes = [];

  BannerAd? _bannerAd;
  bool _isBannerReady = false;

  final _moneyFormatter = NumberFormat.decimalPattern('ko_KR');

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
    final banner = BannerAd(
      adUnitId: 'ca-app-pub-2294312189421130/2526201037',
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
          if (!mounted) return;
          setState(() => _isBannerReady = false);
        },
      ),
    );
    banner.load();
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) _loadGoldenCoins();
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
    _bannerAd?.dispose();
    super.dispose();
  }

  static const String _failureCountKey = 'failureCount';

  Future<void> _loadGoldenCoins() async {
    final coins = await getGoldenCoins();
    if (mounted) setState(() => _goldenCoins = coins);
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
    await setGoldenCoins(coins - 5);
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
    final savedGoal = prefs.getInt(kGoalDaysKey);
    _goalDays = savedGoal != null && savedGoal > 0 ? savedGoal : null;

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
    try {
      if (_reminderTimes.isNotEmpty) {
        await scheduleAllDailyReminders();
        if (!mounted) return;
      }
      final reasonEnabled = prefs.getBool(kReasonNotificationEnabledKey) ?? false;
      if (reasonEnabled) {
        await scheduleReasonReminder();
        if (!mounted) return;
      }
    } catch (e, st) {
      debugPrint('MainScreen: reminder schedule failed: $e\n$st');
    }

    unawaited(bootstrapCoreReminderSchedulesOnAppOpen());
    await syncWidgetData();
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
    final updated = await Navigator.push<List<TimeOfDay>>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderSettingsScreen(
          initialTimes: List.from(_reminderTimes),
          onUpdated: (list) => setState(() => _reminderTimes = list),
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _reminderTimes = updated);
  }

  Future<void> _turnOffReminder() async {
    if (_reminderTimes.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('알림 끄기'),
        content: const Text('모든 리마인더 알림을 끄시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('끄기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await disableDailyReminder();
    setState(() => _reminderTimes = []);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림이 모두 꺼졌습니다.')),
      );
    }
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
                Text('흡연 욕구가 올 때', style: AppTheme.titleLarge),
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
                    '지금까지 $_skippedCigarettes개의 담배를 참았습니다! 조금만 더 힘내세요.',
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                    textAlign: TextAlign.center,
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

  Future<void> _onSmokedTap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('담배를 피우셨나요?'),
        content: const Text(
          '기록하면 실패 횟수만 올라가고, 금연 일수는 그대로 유지됩니다.\n폐 회복도 10% 감소합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('기록'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    _failureCount = (prefs.getInt(_failureCountKey) ?? 0) + 1;
    await prefs.setInt(_failureCountKey, _failureCount);

    final before = prefs.getInt('lungHealth') ?? 100;
    final after = (before - 10).clamp(0, 100);
    await prefs.setInt('lungHealth', after);

    await syncWidgetData();

    setState(() {});

    AdManager.showAd(onAdClosed: () {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('괜찮습니다'),
            content: const Text('금연은 다시 시작하면 됩니다. 오늘부터 다시 함께해요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    });
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

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('금연 현황'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/scoin.png',
                    width: 24,
                    height: 24,
                    errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 24),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_goldenCoins',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '설정',
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    reminderTimes: List.from(_reminderTimes),
                    onReminderUpdated: (list) => setState(() => _reminderTimes = list),
                    onGoToFirstSetup: _confirmAndGoToFirstSetup,
                  ),
                ),
              );
            },
          ),
        ],
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, color: AppTheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Text('금연 시간', style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                  Text(
                    formatDurationLong(_elapsed),
                    style: AppTheme.titleLarge.copyWith(color: AppTheme.primary, fontSize: 16, letterSpacing: 0.2),
                  ),
                ],
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
                  const SizedBox(height: 16),
                  Container(height: 1, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text(formatDurationLong(_elapsed), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '금연 시간 (년/월/일/시/분/초)',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                      ),
                      if (_failureCount > 0)
                        GestureDetector(
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
                    ],
                  ),
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
                              Text('절약 금액', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                              Text('₩$savedMoneyStr', style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('안 핀 담배', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                              Text('$_skippedCigarettes개비', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 알림 / 흡연 욕구 버튼
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
                    label: const Text('흡연 욕구'),
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
            // 전체 알림 끄기 / 담배 피움 / 금연 리셋 한 줄 3등분
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reminderTimes.isEmpty ? null : _turnOffReminder,
                    icon: const Icon(Icons.notifications_off_rounded, size: 16),
                    label: const Text('알림 끄기', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onSmokedTap,
                    icon: const Icon(Icons.smoking_rooms_rounded, size: 16),
                    label: const Text('담배 피움', style: TextStyle(fontSize: 12)),
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
                    onPressed: _resetSmokingStatus,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('리셋', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 이유 / 도우미
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