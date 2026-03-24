import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 사용자가 금연을 결심한 이유를 선택하는 화면
class Screen3Reasons extends StatefulWidget {
  final VoidCallback onNext;
  final int step;
  final int totalSteps;

  const Screen3Reasons({
    super.key,
    required this.onNext,
    this.step = 3,
    this.totalSteps = 9,
  });

  @override
  State<Screen3Reasons> createState() => _Screen3ReasonsState();
}

class _Screen3ReasonsState extends State<Screen3Reasons> {
  final List<String> reasons = [
    '건강 회복을 위해',
    '가족을 위해',
    '경제적 절약',
    '나를 위한 자기관리',
    '습관 개선'
  ];
  String? selectedReason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTheme.progressBar(widget.step, widget.totalSteps),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '금연을 결심한 이유는\n무엇인가요?',
                style: OnboardingTheme.headline,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: reasons.map((reason) {
                  final isSelected = selectedReason == reason;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => selectedReason = reason),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          decoration: OnboardingTheme.optionCardDecoration(selected: isSelected),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                                size: 24,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: OnboardingTheme.bodyBold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: selectedReason != null ? widget.onNext : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.textMuted.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text('계속하기', style: OnboardingTheme.button),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
