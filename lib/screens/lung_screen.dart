import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../ad_manager.dart';
import '../widget/widget_helper.dart';

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

  // 0% → 100% 완전 회복까지 약 30일 (30 * 24h)
  // 30일 / 100% = 0.3일 ≒ 7.2시간당 1% 회복
  static const int _perPercentMs = 30 * 24 * 60 * 60 * 1000 ~/ 100;

  @override
  void initState() {
    super.initState();
    AppAnalytics.screen('lung_screen');

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _initializeLungHealth();

    // ✅ 주기적으로 경과 시간을 확인해 1개월 기준으로 회복량 계산
    _healTimer = Timer.periodic(const Duration(hours: 1), (_) => _healLung());
  }

  Future<void> _initializeLungHealth() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimestamp = prefs.getInt('lastUpdatedTime');
    final savedHealth = prefs.getInt('lungHealth') ?? 0;

    int recoveredHealth = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastTimestamp != null) {
      final diffMs = now - lastTimestamp;
      recoveredHealth = (diffMs ~/ _perPercentMs);
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
    await syncWidgetData();
  }

  Future<void> _healLung() async {
    if (lungHealth >= 100) {
      _healTimer?.cancel();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastTimestamp = prefs.getInt('lastUpdatedTime') ?? DateTime.now().millisecondsSinceEpoch;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMs = now - lastTimestamp;

    final additional = (diffMs ~/ _perPercentMs);
    if (additional <= 0) return;

    setState(() {
      lungHealth = (lungHealth + additional).clamp(0, 100);
      _controller.animateTo(
        lungHealth / 100,
        duration: const Duration(milliseconds: 500),
      );
    });
    await _saveLungHealth();
  }

  Future<void> _confirmSmokeAndDamage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('흡연하시겠습니까?'),
        content: const Text('흡연하면 폐 건강이 10% 감소합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('흡연'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _smokeAndDamage();
    }
  }

  static const String _failureCountKey = 'failureCount';

  Future<void> _smokeAndDamage() async {
    final before = lungHealth;
    final after = (lungHealth - 10).clamp(0, 100);

    setState(() {
      lungHealth = after;
      _controller.animateTo(
        lungHealth / 100,
        duration: const Duration(milliseconds: 500),
      );
    });
    await _saveLungHealth();

    final prefs = await SharedPreferences.getInstance();
    final failureCount = (prefs.getInt(_failureCountKey) ?? 0) + 1;
    await prefs.setInt(_failureCountKey, failureCount);

    AppAnalytics.log('lung_smoke', params: {
      'delta': -10,
      'lung_before': before,
      'lung_after': after,
      'source': 'lung_screen',
    });

    AdManager.showAd(onAdClosed: () {
      if (!mounted) return;
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
      healthColor = AppTheme.success;
    } else if (lungHealth >= 50) {
      healthColor = AppTheme.warning;
    } else {
      healthColor = AppTheme.error;
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('나의 폐 건강'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    Text(
                      '폐는 시간에 따라 회복됩니다',
                      style: AppTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '흡연 시 건강도가 감소하지만, 금연을 유지하면 다시 회복됩니다.\n약 7시간마다 폐 회복 상태가 1%씩 증가하며, 0%에서 100%까지 약 1개월이 걸립니다.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.cardShadowSubtle,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.favorite_rounded, color: healthColor, size: 22),
                        const SizedBox(width: 8),
                        Text('폐 회복 상태', style: AppTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: AppTheme.textMuted.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}% 회복됨',
                      style: AppTheme.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: healthColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _confirmSmokeAndDamage,
                  icon: const Icon(Icons.smoking_rooms_rounded, size: 20),
                  label: const Text('흡연 (-10%)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}