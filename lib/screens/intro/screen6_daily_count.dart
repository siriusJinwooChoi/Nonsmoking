import 'package:flutter/material.dart';
import '../../theme/onboarding_theme.dart';

/// 하루 흡연량(개비 수)을 입력받는 화면
class Screen6DailyCount extends StatefulWidget {
  final Function(int) onNext;
  final int step;
  final int totalSteps;

  const Screen6DailyCount({
    super.key,
    required this.onNext,
    this.step = 6,
    this.totalSteps = 9,
  });

  @override
  State<Screen6DailyCount> createState() => _Screen6DailyCountState();
}

class _Screen6DailyCountState extends State<Screen6DailyCount> {
  final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void handleNext() {
    final cigarettes = int.tryParse(controller.text);
    if (cigarettes != null) {
      widget.onNext(cigarettes);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('숫자를 정확히 입력해주세요.')),
      );
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '하루에 피우는 담배\n개비 수를 입력해주세요.',
                style: OnboardingTheme.headline,
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: OnboardingTheme.bodyBold,
                decoration: OnboardingTheme.inputDecoration(
                  labelText: '개비 수',
                  hintText: '예: 10',
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: OnboardingTheme.primaryButton(onPressed: handleNext, label: '계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}
