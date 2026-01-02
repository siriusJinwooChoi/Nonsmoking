import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

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
    AppAnalytics.screen('lung_screen');

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _initializeLungHealth();

    // ✅ 1시간마다 1%씩 회복
    _healTimer = Timer.periodic(const Duration(hours: 1), (_) => _healLung());
  }

  Future<void> _initializeLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimestamp = prefs.getInt('lastUpdatedTime');
    final savedHealth = prefs.getInt('lungHealth') ?? 0;

    int recoveredHealth = 0;
    if (lastTimestamp != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final diffHours = ((now - lastTimestamp) / 3600000).floor();
      recoveredHealth = diffHours;
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

  Future<void> _saveLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lungHealth', lungHealth);
    await prefs.setInt('lastUpdatedTime', DateTime.now().millisecondsSinceEpoch);
  }

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

  Future<void> _confirmSmokeAndDamage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🚬 흡연하시겠습니까?'),
        content: const Text('흡연하면 폐 건강이 10% 감소합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('흡연'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _smokeAndDamage();
    }
  }

  void _smokeAndDamage() {
    final before = lungHealth;
    final after = (lungHealth - 10).clamp(0, 100);

    setState(() {
      lungHealth = after;
      _controller.animateTo(
        lungHealth / 100,
        duration: const Duration(milliseconds: 500),
      );
    });
    _saveLungHealth();

    // ✅ Analytics
    AppAnalytics.log('lung_smoke', params: {
      'delta': -10,
      'lung_before': before,
      'lung_after': after,
      'source': 'lung_screen',
    });
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

    Color healthColor;
    if (lungHealth >= 80) {
      healthColor = Colors.teal;
    } else if (lungHealth >= 50) {
      healthColor = Colors.orangeAccent;
    } else {
      healthColor = Colors.redAccent;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.redAccent,
        title: const Text(
          '나의 폐 건강 상태 🫁',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 3,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  child: Column(
                    children: [
                      const Text(
                        '폐는 시간에 따라 회복됩니다 💨',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '흡연 시 건강도가 감소하지만, 금연을 유지하면 다시 회복됩니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(
                height: 230,
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

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.monitor_heart, color: Colors.teal),
                        const SizedBox(width: 6),
                        Text(
                          '폐 회복 상태',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}% 회복됨',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: healthColor),
                    ),
                  ],
                ),
              ),

              ElevatedButton.icon(
                onPressed: _confirmSmokeAndDamage,
                icon: const Icon(Icons.smoking_rooms, size: 22),
                label: const Text(
                  '흡연 (-10%)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}