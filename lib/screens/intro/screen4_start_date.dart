import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 금연 시작일을 설정하는 화면
class Screen4StartDate extends StatefulWidget {
  final VoidCallback onNext;
  final int step;
  final int totalSteps;

  const Screen4StartDate({
    super.key,
    required this.onNext,
    this.step = 4,
    this.totalSteps = 9,
  });

  @override
  State<Screen4StartDate> createState() => _Screen4StartDateState();
}

class _Screen4StartDateState extends State<Screen4StartDate> {
  DateTime? selectedDate;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnboardingTheme.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingTheme.progressBar(widget.step, widget.totalSteps),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '금연을 시작한 날짜를\n선택해주세요',
                      style: OnboardingTheme.headline,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(context),
                      icon: const Icon(Icons.calendar_today_rounded, size: 20),
                      label: const Text('날짜 선택'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (selectedDate != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${selectedDate!.year}.${selectedDate!.month.toString().padLeft(2, '0')}.${selectedDate!.day.toString().padLeft(2, '0')}',
                          style: OnboardingTheme.headlineSub.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: selectedDate != null ? widget.onNext : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
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
