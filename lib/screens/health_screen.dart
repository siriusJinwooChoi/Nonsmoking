import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../theme/app_theme.dart';

class HealthStage {
  final String label;
  final int minutes;
  final String description;

  const HealthStage({
    required this.label,
    required this.minutes,
    required this.description,
  });
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  DateTime? _startTime;
  Duration quitDuration = Duration.zero;
  Timer? _timer;

  final List<HealthStage> healthStages = const [
    HealthStage(
      label: '20분',
      minutes: 20,
      description: '심박수와 혈압이 내려가 금연 전보다 안정화되기 시작합니다.',
    ),
    HealthStage(
      label: '8시간',
      minutes: 8 * 60,
      description: '혈중 일산화탄소 농도가 감소하고 산소 운반이 개선됩니다.',
    ),
    HealthStage(
      label: '24시간',
      minutes: 24 * 60,
      description: '심혈관 부담이 줄기 시작하며 심장질환 위험 감소가 시작됩니다.',
    ),
    HealthStage(
      label: '48시간',
      minutes: 48 * 60,
      description: '니코틴이 대부분 배출되고 후각·미각 회복이 시작됩니다.',
    ),
    HealthStage(
      label: '72시간',
      minutes: 72 * 60,
      description: '기관지가 이완되며 호흡이 이전보다 편해지는 경우가 많습니다.',
    ),
    HealthStage(
      label: '2주',
      minutes: 14 * 24 * 60,
      description: '혈액순환 개선이 본격화되어 활동 시 숨참이 완화될 수 있습니다.',
    ),
    HealthStage(
      label: '1개월',
      minutes: 30 * 24 * 60,
      description: '기침·가래가 줄고 폐의 섬모 기능 회복이 진행됩니다.',
    ),
    HealthStage(
      label: '3개월',
      minutes: 90 * 24 * 60,
      description: '폐기능이 유의하게 개선되어 일상 체력이 좋아질 수 있습니다.',
    ),
    HealthStage(
      label: '6개월',
      minutes: 180 * 24 * 60,
      description: '호흡기 증상이 더 완화되고 회복 체감이 커지는 시기입니다.',
    ),
    HealthStage(
      label: '9개월',
      minutes: 270 * 24 * 60,
      description: '기침/숨가쁨 완화가 지속되고 감염 대응력이 좋아질 수 있습니다.',
    ),
    HealthStage(
      label: '1년',
      minutes: 365 * 24 * 60,
      description: '관상동맥 심장질환 위험이 절반으로 감소합니다.',
    ),
    HealthStage(
      label: '5년',
      minutes: 365 * 24 * 60 * 5,
      description: '뇌졸중 위험이 비흡연자 수준에 가까워질 수 있습니다.',
    ),
    HealthStage(
      label: '10년',
      minutes: 365 * 24 * 60 * 10,
      description: '폐암 사망 위험이 흡연 지속 대비 약 절반으로 감소합니다.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadStartTime();
  }

  Future<void> _loadStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final millis = prefs.getInt('startTime');

    if (millis != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(millis);
      _updateDuration();

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _updateDuration();
      });
    }
  }

  void _updateDuration() {
    if (_startTime == null || !mounted) return;
    final now = DateTime.now();
    setState(() {
      quitDuration = now.difference(_startTime!);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);

    if (days > 0) {
      return '$days일 $hours시간 $minutes분';
    }
    if (hours > 0) {
      return '$hours시간 $minutes분';
    }
    return '$minutes분';
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = quitDuration.inMinutes;
    const maxMinutes = 5256000; // 10년
    final progress = (totalMinutes / maxMinutes).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('건강 개선 현황'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('금연 진행률: $percent%', style: AppTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '경과 시간: ${_formatDuration(quitDuration)}',
                    style: AppTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      backgroundColor: AppTheme.textMuted.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('건강 회복 단계', style: AppTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              itemCount: healthStages.length,
              itemBuilder: (context, index) {
                final stage = healthStages[index];
                final completed = totalMinutes >= stage.minutes;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppTheme.cardShadowSubtle,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: completed ? AppTheme.success : AppTheme.textMuted,
                        size: 24,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stage.label, style: AppTheme.titleMedium.copyWith(fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(stage.description, style: AppTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}