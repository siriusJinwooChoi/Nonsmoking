import 'package:flutter/material.dart';
import '../../theme/onboarding_theme.dart';

/// 흡연 기간(년/월/일)을 입력받는 화면
class Screen5Duration extends StatefulWidget {
  final Function(int) onNext;
  final int step;
  final int totalSteps;

  const Screen5Duration({
    super.key,
    required this.onNext,
    this.step = 5,
    this.totalSteps = 9,
  });

  @override
  State<Screen5Duration> createState() => _Screen5DurationState();
}

class _Screen5DurationState extends State<Screen5Duration> {
  int years = 0;
  int months = 0;
  int days = 0;

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
                '흡연을 얼마나\n오래 하셨나요?',
                style: OnboardingTheme.headline,
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _dropCard(
                      label: '년',
                      value: years,
                      itemCount: 51,
                      onChanged: (val) => setState(() => years = val!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dropCard(
                      label: '월',
                      value: months,
                      itemCount: 12,
                      onChanged: (val) => setState(() => months = val!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dropCard(
                      label: '일',
                      value: days,
                      itemCount: 31,
                      onChanged: (val) => setState(() => days = val!),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: OnboardingTheme.primaryButton(
                onPressed: () {
                  final totalDays = years * 365 + months * 30 + days;
                  widget.onNext(totalDays);
                },
                label: '계속하기',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropCard({
    required String label,
    required int value,
    required int itemCount,
    required ValueChanged<int?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(label, style: OnboardingTheme.bodyBold.copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            items: List.generate(itemCount, (i) => DropdownMenuItem(value: i, child: Text('$i', style: OnboardingTheme.body))),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
