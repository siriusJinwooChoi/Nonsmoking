import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class HealthStage {
  final String label;
  final int minutes;
  final String description;
  final String emoji;

  const HealthStage({
    required this.label,
    required this.minutes,
    required this.description,
    required this.emoji,
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
  int _goalDays = 0;

  // WHO·CDC·NHS 기반 금연 후 건강 회복 단계
  final List<HealthStage> healthStages = const [
    HealthStage(
      label: '20분',
      minutes: 20,
      emoji: '❤️',
      description: '심박수·혈압이 정상으로 내려가고 손발이 따뜻해져요.',
    ),
    HealthStage(
      label: '8시간',
      minutes: 8 * 60,
      emoji: '🫁',
      description: '혈중 일산화탄소가 절반으로 줄고, 혈액이 산소를 더 잘 운반해요.',
    ),
    HealthStage(
      label: '24시간',
      minutes: 24 * 60,
      emoji: '💪',
      description: '니코틴이 거의 소진되고 심장마비 위험이 줄어들기 시작해요.',
    ),
    HealthStage(
      label: '48시간',
      minutes: 48 * 60,
      emoji: '👃',
      description: '니코틴이 완전히 빠져나가고 후각·미각이 예민해져요.',
    ),
    HealthStage(
      label: '72시간',
      minutes: 72 * 60,
      emoji: '🌬️',
      description: '기관지가 이완되어 호흡이 훨씬 편안해졌을 거예요.',
    ),
    HealthStage(
      label: '2주',
      minutes: 14 * 24 * 60,
      emoji: '🚶',
      description: '말초 혈액순환이 좋아져 운동하거나 걸을 때 덜 힘들어요.',
    ),
    HealthStage(
      label: '1개월',
      minutes: 30 * 24 * 60,
      emoji: '😮‍💨',
      description: '만성 기침·가래가 줄고, 폐 섬모가 재생되어 자정 능력이 높아져요.',
    ),
    HealthStage(
      label: '3개월',
      minutes: 90 * 24 * 60,
      emoji: '🏃',
      description: '폐 기능이 최대 30% 향상될 수 있고 체력이 눈에 띄게 좋아져요.',
    ),
    HealthStage(
      label: '6개월',
      minutes: 180 * 24 * 60,
      emoji: '😴',
      description: '스트레스에 더 잘 견디고 수면의 질이 개선돼요.',
    ),
    HealthStage(
      label: '1년',
      minutes: 365 * 24 * 60,
      emoji: '🫀',
      description: '관상동맥 질환 위험이 흡연자의 절반 수준으로 줄어들어요. (WHO)',
    ),
    HealthStage(
      label: '5년',
      minutes: 365 * 24 * 60 * 5,
      emoji: '🧠',
      description: '뇌졸중 위험이 비흡연자와 거의 같은 수준이 돼요. (CDC)',
    ),
    HealthStage(
      label: '10년',
      minutes: 365 * 24 * 60 * 10,
      emoji: '🎗️',
      description: '폐암 사망 위험이 현재 흡연자의 절반으로 떨어져요. (CDC)',
    ),
    HealthStage(
      label: '15년',
      minutes: 365 * 24 * 60 * 15,
      emoji: '🌟',
      description: '심장병 위험이 담배를 피운 적 없는 사람과 같아져요. (NHS)',
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

    final goal = prefs.getInt('goalDays') ?? 0;
    if (!mounted) return;
    setState(() => _goalDays = goal);
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
    final goalMinutes = _goalDays > 0 ? _goalDays * 24 * 60 : 5256000;
    final progress = (totalMinutes / goalMinutes).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(1);
    final goalLabel = _goalDays > 0 ? '$_goalDays일' : '10년';

    final completedCount = healthStages.where((s) => totalMinutes >= s.minutes).length;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('건강 개선 현황')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20, 0, 20,
          MediaQuery.of(context).padding.bottom + 32,
        ),
        children: [
          // ─── 히어로 진행 카드 ────────────────────────
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withValues(alpha: 0.82),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '건강 회복 여정',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDuration(quitDuration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            '금연 중',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$completedCount/${healthStages.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '단계 달성',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '목표($goalLabel) 달성률',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ─── 섹션 헤더 ────────────────────────────────
          Row(
            children: [
              Text(
                '회복 단계',
                style: AppTheme.titleMedium.copyWith(fontSize: 17),
              ),
              const SizedBox(width: 8),
              Text(
                'WHO·CDC·NHS 기반',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ─── 타임라인 ─────────────────────────────────
          ...List.generate(healthStages.length, (index) {
            final stage = healthStages[index];
            final completed = totalMinutes >= stage.minutes;
            final isNext = !completed &&
                (index == 0 || totalMinutes >= healthStages[index - 1].minutes);
            final isLast = index == healthStages.length - 1;

            return _TimelineItem(
              stage: stage,
              completed: completed,
              isNext: isNext,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.stage,
    required this.completed,
    required this.isNext,
    required this.isLast,
  });

  final HealthStage stage;
  final bool completed;
  final bool isNext;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dotColor = completed
        ? AppTheme.success
        : isNext
            ? AppTheme.primary
            : AppTheme.border;

    final cardBg = completed
        ? AppTheme.success.withValues(alpha: 0.06)
        : isNext
            ? AppTheme.primary.withValues(alpha: 0.05)
            : AppTheme.surfaceCard;

    final cardBorder = completed
        ? AppTheme.success.withValues(alpha: 0.2)
        : isNext
            ? AppTheme.primary.withValues(alpha: 0.25)
            : AppTheme.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── 타임라인 선 + 점 ──────────────────────
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // 점
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: completed
                        ? AppTheme.success
                        : isNext
                            ? AppTheme.primary
                            : AppTheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2),
                    boxShadow: (completed || isNext)
                        ? [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Center(
                    child: completed
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                        : isNext
                            ? const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16)
                            : Text(
                                stage.emoji,
                                style: const TextStyle(fontSize: 14),
                              ),
                  ),
                ),
                // 연결선
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: completed
                            ? AppTheme.success.withValues(alpha: 0.4)
                            : AppTheme.border,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ─── 내용 카드 ────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                stage.emoji,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                stage.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: completed
                                      ? AppTheme.success
                                      : isNext
                                          ? AppTheme.primary
                                          : AppTheme.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (isNext) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    '다음 목표',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            stage.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (completed)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.verified_rounded,
                          color: AppTheme.success.withValues(alpha: 0.7),
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}