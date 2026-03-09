import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 금연을 시작한 사용자를 응원하는 첫 번째 온보딩 화면
class Screen1Encourage extends StatelessWidget {
  final VoidCallback onNext;
  final int step;
  final int totalSteps;

  const Screen1Encourage({
    super.key,
    required this.onNext,
    this.step = 1,
    this.totalSteps = 9,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTheme.progressBar(step, totalSteps),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '오늘 당신은 금연을 선택했어요.',
                      style: OnboardingTheme.headline,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '삶을 바꾸게 해드릴게요.\n당신을 응원합니다!',
                      style: OnboardingTheme.headlineSub,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    OnboardingTheme.primaryButton(
                      onPressed: onNext,
                      label: '계속하기',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
