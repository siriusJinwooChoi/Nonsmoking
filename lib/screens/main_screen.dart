import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

// ✅ IntroFlowWrapper를 사용하기 위해 main.dart를 import
// 프로젝트 구조에 맞게 경로를 조정하세요.
// 예) import '../main.dart'; 혹은 import 'package:your_app/main.dart';
import '../main.dart';

class MainScreen extends StatefulWidget {
  final VoidCallback onAlarmTap;
  final VoidCallback onCravingTap;
  final VoidCallback onResetTap;
  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;

  const MainScreen({
    super.key,
    required this.onAlarmTap,
    required this.onCravingTap,
    required this.onResetTap,
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

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    tzData.initializeTimeZones();
    _initNotifications();
    _loadPersistedData();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings);
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

      final totalCigs =
          (widget.dailyCigarettes / (24 * 60 * 60)) * seconds;
      final costPerCig = widget.cigarettesPerPack > 0
          ? widget.pricePerPack / widget.cigarettesPerPack
          : 0;
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
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reminderHour', picked.hour);
      await prefs.setInt('reminderMinute', picked.minute);
      setState(() => _reminderTime = picked);
      _scheduleReminderNotification(picked);
    }
  }

  Future<void> _scheduleReminderNotification(TimeOfDay time) async {
    // 이 메서드는 채널/권한 초기화 이후, 원하는 구현을 이어가면 됩니다.
    // (여기서는 예약 시각 계산까지만 해둡니다.)
    final now = DateTime.now();
    var scheduledDate =
    DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      importance: Importance.max,
      priority: Priority.high,
    );
    final notificationDetails = NotificationDetails(android: androidDetails);

    // 사용 중인 flutter_local_notifications 버전에 맞는 API로 스케줄 등록하세요.
    // (여기서는 실제 예약 호출은 생략)
    // 예: await _notificationsPlugin.zonedSchedule(...) 또는 show() 등
  }

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inHours)}:"
        "${twoDigits(d.inMinutes.remainder(60))}:"
        "${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resetSmokingStatus() async {
    final prefs = await SharedPreferences.getInstance();

    // 시작 시간 초기화
    final now = DateTime.now();
    await prefs.setInt('startTime', now.millisecondsSinceEpoch);
    setState(() => _startTime = now);

    // 폐 건강 -10 감소 (LungScreen과 연동)
    final currentLungHealth = prefs.getInt('lungHealth') ?? 100;
    final newLungHealth = (currentLungHealth - 10).clamp(0, 100);
    await prefs.setInt('lungHealth', newLungHealth);

    widget.onResetTap();
  }

  // =========================
  // ✅ 설정 시트 & 동작 모음
  // =========================

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('설정 초기화 (온보딩 다시하기)'),
                subtitle: const Text('저장된 설정을 초기화하고 처음 화면으로 돌아갑니다.'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _resetToOnboarding();
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off),
                title: const Text('알림 모두 해제'),
                subtitle: const Text('설정된 모든 푸시 알림을 취소합니다.'),
                onTap: () async {
                  await _notificationsPlugin.cancelAll();
                  if (mounted) Navigator.of(context).pop();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('알림이 모두 해제되었습니다.')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('금연 시작일 다시 설정'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _repickStartDate();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services),
                title: const Text('화면 데이터(절약/시간/개비) 초기화'),
                subtitle: const Text('표시값을 0 기준으로 다시 계산합니다.'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _softResetStats();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _resetToOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // 주요 설정/표시 값 초기화
    await prefs.setBool('isConfigured', false);
    await prefs.remove('startTime');
    await prefs.remove('reminderHour');
    await prefs.remove('reminderMinute');
    // 필요 시 폐 건강도 초기화
    // await prefs.remove('lungHealth');

    // 모든 알림 취소
    await _notificationsPlugin.cancelAll();

    // 온보딩 첫 화면(= IntroFlowWrapper)로 완전 전환
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const IntroFlowWrapper()),
          (route) => false,
    );
  }

  Future<void> _repickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startTime ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('startTime', picked.millisecondsSinceEpoch);
      setState(() => _startTime = picked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('시작일이 ${DateFormat('yyyy년 MM월 dd일').format(picked)}로 변경되었습니다.')),
      );
    }
  }

  Future<void> _softResetStats() async {
    // 시작 시각을 지금으로 덮어쓰면, 표시값(경과/절약/개비)이 0 기준으로 다시 누적됩니다.
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('startTime', now.millisecondsSinceEpoch);
    setState(() {
      _startTime = now;
      _elapsed = Duration.zero;
      _savedMoney = 0;
      _skippedCigarettes = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('표시값이 초기화되었습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedStart = _startTime != null
        ? DateFormat('yyyy년 MM월 dd일').format(_startTime!)
        : '';
    final days =
    _startTime != null ? DateTime.now().difference(_startTime!).inDays : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: const Text('금연 현황'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 카드: 기본 누적 정보
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("📅 시작일: $formattedStart",
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 6),
                  Text("📈 누적일: ${days}일",
                      style: const TextStyle(fontSize: 16)),
                  const Divider(height: 24),
                  Text("⏳ 금연 시간: ${formatDuration(_elapsed)}",
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("💰 절약 금액: ₩${_savedMoney.toStringAsFixed(0)}",
                      style:
                      const TextStyle(fontSize: 20, color: Colors.green)),
                  const SizedBox(height: 8),
                  Text("🚭 안 핀 담배 수: $_skippedCigarettes개비",
                      style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 알림 설정 / 욕구 참기
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ElevatedButton.icon(
                        onPressed: _pickReminderTime,
                        icon: const Icon(Icons.notifications),
                        label: Text(_reminderTime == null
                            ? '알림 설정'
                            : '⏰ ${_reminderTime!.format(context)}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigoAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: ElevatedButton.icon(
                        onPressed: widget.onCravingTap,
                        icon: const Icon(Icons.self_improvement),
                        label: const Text('욕구 참기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 알람 받기
            Center(
              child: ElevatedButton.icon(
                onPressed: widget.onAlarmTap,
                icon: const Icon(Icons.alarm),
                label: const Text('알람 받기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // 금연 리셋 (표시상 리셋 + 폐건강 -10)
            Center(
              child: ElevatedButton.icon(
                onPressed: _resetSmokingStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('금연 리셋'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade100,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}