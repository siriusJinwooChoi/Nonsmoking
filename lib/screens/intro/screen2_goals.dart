import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 금연의 장점을 소개하는 두 번째 인트로 화면
class Screen2Goals extends StatelessWidget {
  final VoidCallback onNext;
  final int step;
  final int totalSteps;

  const Screen2Goals({
    super.key,
    required this.onNext,
    this.step = 2,
    this.totalSteps = 9,
  });

  static const List<({String title, String subtitle, IconData icon})> _goals = [
    (title: '건강 증진 및 질병 예방', subtitle: '심장병, 폐암, 뇌졸중, COPD 등 예방', icon: Icons.favorite_rounded),
    (title: '수명 연장', subtitle: '심장 질환 및 암 발생률 감소', icon: Icons.schedule_rounded),
    (title: '가족 건강 보호', subtitle: '간접흡연 방지, 가족 건강 지킴', icon: Icons.family_restroom_rounded),
    (title: '경제적 부담 감소', subtitle: '담배 비용 및 질병 치료비 절약', icon: Icons.savings_rounded),
    (title: '자기 통제력 강화', subtitle: '통제력 회복, 자존감 향상', icon: Icons.emoji_events_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTheme.progressBar(step, totalSteps),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '금연을 통해 얻을 수 있는 것들',
                style: OnboardingTheme.headline,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: _goals.map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.success),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(g.title, style: OnboardingTheme.bodyBold.copyWith(fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(g.subtitle, style: OnboardingTheme.body.copyWith(fontSize: 13, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(g.icon, size: 22, color: AppTheme.primary.withOpacity(0.8)),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: OnboardingTheme.primaryButton(onPressed: onNext, label: '계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}
