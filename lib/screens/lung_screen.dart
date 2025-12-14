import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

class LungScreen extends StatefulWidget {
  const LungScreen({super.key});

  @override
  State<LungScreen> createState() => _LungScreenState();
}

class _LungScreenState extends State<LungScreen> with TickerProviderStateMixin {
  int lungHealth = 0; // 0 ~ 100
  late AnimationController _controller;
  Timer? _healTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _initializeLungHealth();

    // ✅ 1시간마다 1%씩 회복
    _healTimer = Timer.periodic(const Duration(hours: 1), (_) => _healLung());
  }

  /// 앱 실행 시 저장된 데이터 + 경과 시간 기반으로 상태 초기화
  Future<void> _initializeLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimestamp = prefs.getInt('lastUpdatedTime');
    final savedHealth = prefs.getInt('lungHealth') ?? 0;

    int recoveredHealth = 0;
    if (lastTimestamp != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // ✅ 1시간 = 3600000ms 기준으로 회복량 계산
      final diffHours = ((now - lastTimestamp) / 3600000).floor();
      recoveredHealth = diffHours; // 1시간에 1%
    }

    lungHealth = (savedHealth + recoveredHealth).clamp(0, 100);

    _controller.animateTo(
      lungHealth / 100,
      duration: const Duration(seconds: 2),
      curve: Curves.easeOut,
    );

    await _saveLungHealth();
    setState(() {});
  }

  /// 상태 저장
  Future<void> _saveLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lungHealth', lungHealth);
    await prefs.setInt('lastUpdatedTime', DateTime.now().millisecondsSinceEpoch);
  }

  /// 1시간마다 1%씩 회복
  void _healLung() {
    if (lungHealth < 100) {
      setState(() {
        lungHealth++;
        _controller.animateTo(
          lungHealth / 100,
          duration: const Duration(milliseconds: 500),
        );
      });
      _saveLungHealth();
    } else {
      _healTimer?.cancel();
    }
  }

  /// 흡연 시 -10%
  void _smokeAndDamage() {
    setState(() {
      lungHealth = (lungHealth - 10).clamp(0, 100);
      _controller.animateTo(
        lungHealth / 100,
        duration: const Duration(milliseconds: 500),
      );
    });
    _saveLungHealth();
  }

  @override
  void dispose() {
    _healTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = lungHealth / 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('나의 폐 상태'),
        backgroundColor: Colors.redAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: SizedBox(
                height: 240,
                child: Lottie.asset(
                  'assets/lung_recover.json',
                  controller: _controller,
                  onLoaded: (composition) {
                    _controller.duration = composition.duration;
                  },
                  repeat: false,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 30),

            // 회복 상태
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '폐 회복 상태',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}% 완료',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // 흡연 버튼
            ElevatedButton.icon(
              onPressed: _smokeAndDamage,
              icon: const Icon(Icons.smoking_rooms),
              label: const Text('흡연: -10%', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}