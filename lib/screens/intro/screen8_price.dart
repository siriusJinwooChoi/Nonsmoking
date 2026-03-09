import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 담배 1갑 가격을 입력받는 화면
class Screen8Price extends StatefulWidget {
  final Function(int) onNext;
  final int step;
  final int totalSteps;

  const Screen8Price({
    super.key,
    required this.onNext,
    this.step = 8,
    this.totalSteps = 9,
  });

  @override
  State<Screen8Price> createState() => _Screen8PriceState();
}

class _Screen8PriceState extends State<Screen8Price> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleNext() {
    final price = int.tryParse(_controller.text);
    if (price != null && price > 0) {
      widget.onNext(price);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격을 숫자로 정확히 입력해주세요.')),
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
                '담배 1갑의 가격을\n입력해주세요.',
                style: OnboardingTheme.headline,
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                style: OnboardingTheme.bodyBold,
                decoration: OnboardingTheme.inputDecoration(
                  labelText: '가격 (₩)',
                  hintText: '예: 4500',
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: OnboardingTheme.primaryButton(onPressed: _handleNext, label: '계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}
