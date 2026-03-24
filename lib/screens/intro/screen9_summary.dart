import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 금연 요약 정보를 보여주는 화면
class Screen9Summary extends StatelessWidget {
  final VoidCallback onNext;
  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;
  final int durationDays;
  final int step;
  final int totalSteps;

  const Screen9Summary({
    super.key,
    required this.onNext,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
    required this.durationDays,
    this.step = 9,
    this.totalSteps = 9,
  });

  @override
  Widget build(BuildContext context) {
    const int oneYearDays = 365;
    final int notSmokedInOneYear = dailyCigarettes * oneYearDays;
    final double costPerCigarette =
        cigarettesPerPack > 0 ? pricePerPack / cigarettesPerPack : 0;
    final int savedMoneyYear = (costPerCigarette * notSmokedInOneYear).round();
    final int smokedSoFar = dailyCigarettes * durationDays;

    final comma = NumberFormat.decimalPattern('ko_KR');
    final savedMoneyYearStr = comma.format(savedMoneyYear);
    final notSmokedInOneYearStr = comma.format(notSmokedInOneYear);
    final smokedSoFarStr = comma.format(smokedSoFar);

    final List<String> goals = [
      '폐 기능 향상',
      '심혈관 건강 개선',
      '피부톤 회복',
      '체력 증가',
    ];

    return Scaffold(
      backgroundColor: OnboardingTheme.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTheme.progressBar(step, totalSteps),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1년간 달성할 수 있는 목표', style: OnboardingTheme.headline),
                    const SizedBox(height: 16),
                    ...goals.map((goal) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 22, color: AppTheme.success),
                              const SizedBox(width: 12),
                              Text(goal, style: OnboardingTheme.bodyBold),
                            ],
                          ),
                        )),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('1년간 절약할 수 있는 금액', style: OnboardingTheme.body.copyWith(color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text('₩$savedMoneyYearStr', style: OnboardingTheme.headline.copyWith(color: AppTheme.primary, fontSize: 24)),
                          const SizedBox(height: 16),
                          Text('1년간 피우지 않을 담배 수', style: OnboardingTheme.body.copyWith(color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text('$notSmokedInOneYearStr개비', style: OnboardingTheme.bodyBold),
                          const SizedBox(height: 16),
                          Text('현재까지 핀 담배 개수(추정)', style: OnboardingTheme.body.copyWith(color: AppTheme.textSecondary, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('$smokedSoFarStr개비', style: OnboardingTheme.bodyBold),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: OnboardingTheme.primaryButton(onPressed: onNext, label: '시작하기'),
            ),
          ],
        ),
      ),
    );
  }
}