import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ SystemNavigator.pop
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'reason_why_screen.dart';
import 'nonsmoke_helper_screen.dart';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

// ✅ WorkManager 알림(네 프로젝트 구조 기준)
import '../notifications/daily_reminder_worker.dart';

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

class _MainScreenState extends State<MainScreen> {
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
    AppAnalytics.screen('main_screen');
    _loadPersistedData();
    _loadBannerAd();
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

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inHours)}:"
        "${twoDigits(d.inMinutes.remainder(60))}:"
        "${twoDigits(d.inSeconds.remainder(60))}";
  }

  Future<void> _resetSmokingStatus() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('⚠️ 금연 리셋'),
          content: const Text('정말로 금연 리셋을 진행하시겠습니까?\n기록이 초기화됩니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
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
      backgroundColor: const Color(0xFFF3F7F5),
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        title: const Text('금연 현황 🌿', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 3,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: _confirmAndGoToFirstSetup, // ✅ 변경
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상단 카드
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("📅 시작일: $formattedStart",
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text("📈 누적일: ${days}일",
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const Divider(height: 24, color: Colors.white70),
                  Text("⏳ 금연 시간: ${formatDuration(_elapsed)}",
                      style: const TextStyle(
                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("💰 절약 금액: ₩$savedMoneyStr",
                      style: const TextStyle(
                          color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text("🚭 안 핀 담배 수: $_skippedCigarettes개비",
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
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
                    icon: const Icon(Icons.notifications_active),
                    label: Text(
                      _reminderTime == null ? '알림 설정' : '⏰ ${_reminderTime!.format(context)}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigoAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onCravingTap,
                    icon: const Icon(Icons.self_improvement),
                    label: const Text('욕구 참기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),

            // ✅ 알림 끄기 버튼(알림이 설정되어 있을 때만)
            if (_reminderTime != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _turnOffReminder,
                icon: const Icon(Icons.notifications_off),
                label: const Text('알림 끄기'),
              ),
            ],

            const SizedBox(height: 16),

            // 리셋 버튼
            ElevatedButton.icon(
              onPressed: _resetSmokingStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('금연 리셋'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),

            // 이유 / 도우미 버튼
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.format_list_bulleted),
                    label: const Text('금연할 이유'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReasonWhyScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.volunteer_activism),
                    label: const Text('금연 도우미'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NonsmokeHelperScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),

            // 광고 영역
            if (_isBannerReady && _bannerAd != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Align(
                  alignment: Alignment.center,
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