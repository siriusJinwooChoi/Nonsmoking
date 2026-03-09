import 'package:flutter/material.dart';
import '../../theme/onboarding_theme.dart';

/// 한 갑에 담배 개비 수를 입력받는 화면
class Screen7PerPack extends StatefulWidget {
  final Function(int) onNext;
  final int step;
  final int totalSteps;

  const Screen7PerPack({
    super.key,
    required this.onNext,
    this.step = 7,
    this.totalSteps = 9,
  });

  @override
  State<Screen7PerPack> createState() => _Screen7PerPackState();
}

class _Screen7PerPackState extends State<Screen7PerPack> {
  final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void handleNext() {
    final cigarettesPack = int.tryParse(controller.text);
    if (cigarettesPack != null) {
      widget.onNext(cigarettesPack);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정확한 숫자를 입력해주세요.')),
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
                '한 갑에 들어있는 담배\n개비 수를 입력해주세요.',
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
                  hintText: '예: 20',
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
