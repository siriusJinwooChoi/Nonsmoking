import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ SystemNavigator.pop
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'reason_why_screen.dart';
import 'nonsmoke_helper_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';

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
  Timer? _timer;
  TimeOfDay? _reminderTime;

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
    }
  }

  void _loadBannerAd() {
    final banner = BannerAd(
      adUnitId: 'ca-app-pub-2294312189421130/2526201037',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerReady = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _isBannerReady = false);
        },
      ),
    );
    banner.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt('startTime');
    final hour = prefs.getInt('reminderHour');
    final minute = prefs.getInt('reminderMinute');

    if (millis != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(millis);
    } else {
      _startTime = DateTime.now();
      await prefs.setInt('startTime', _startTime!.millisecondsSinceEpoch);
    }

    if (hour != null && minute != null) {
      _reminderTime = TimeOfDay(hour: hour, minute: minute);
    }

    _startTimer();
    await syncWidgetData();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime == null) return;

      final now = DateTime.now();
      final diff = now.difference(_startTime!);
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
    });
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reminderHour', picked.hour);
      await prefs.setInt('reminderMinute', picked.minute);
      setState(() => _reminderTime = picked);

      // ✅ WorkManager 기반 알림 ON
      await enableDailyReminder(picked);

      // ✅ Analytics
      await AppAnalytics.log('reminder_set', params: {
        'hour': picked.hour,
        'minute': picked.minute,
        'source': 'main_screen',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('매일 ${picked.format(context)}에 알림이 설정되었습니다.')),
        );
      }
    }
  }

  Future<void> _turnOffReminder() async {
    if (_reminderTime == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('알림 끄기'),
        content: const Text('매일 리마인더 알림을 끄시겠습니까?'),
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

    final prev = _reminderTime!;
    await disableDailyReminder();

    setState(() => _reminderTime = null);

    // ✅ Analytics
    await AppAnalytics.log('reminder_off', params: {
      'hour': prev.hour,
      'minute': prev.minute,
      'source': 'main_screen',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림이 꺼졌습니다.')),
      );
    }
  }

  /// 금연 시간을 년/월/일/시간/분/초로 표시
  String formatDurationLong(Duration d) {
    final totalDays = d.inDays;
    final years = totalDays ~/ 365;
    final remainderDays = totalDays % 365;
    final months = remainderDays ~/ 30;
    final days = remainderDays % 30;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
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
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '설정',
            onPressed: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    reminderTime: _reminderTime,
                    onReminderUpdated: (t) => setState(() => _reminderTime = t),
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
                border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 1),
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
                    color: AppTheme.primary.withOpacity(0.25),
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
                      Text('시작일', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
                      Text(formattedStart, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('누적일', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
                      Text('$days일', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text(formatDurationLong(_elapsed), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('금연 시간 (년/월/일/시/분/초)', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('절약 금액', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
                              Text('₩$savedMoneyStr', style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('안 핀 담배', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
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

            // 알림 / 욕구 버튼
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickReminderTime,
                    icon: const Icon(Icons.notifications_active_rounded, size: 20),
                    label: Text(_reminderTime == null ? '알림 설정' : _reminderTime!.format(context)),
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
                    onPressed: widget.onCravingTap,
                    icon: const Icon(Icons.self_improvement_rounded, size: 20),
                    label: const Text('욕구 참기'),
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
            if (_reminderTime != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _turnOffReminder,
                icon: const Icon(Icons.notifications_off_rounded, size: 18),
                label: const Text('알림 끄기'),
              ),
            ],
            const SizedBox(height: 16),

            // 리셋 버튼
            ElevatedButton.icon(
              onPressed: _resetSmokingStatus,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('금연 리셋'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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