import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/onboarding_theme.dart';

/// 사용자가 금연을 결심한 이유를 선택하는 화면 (프리셋 + 기타 직접 입력)
class Screen3Reasons extends StatefulWidget {
  /// 선택한 이유 문구(프리셋 또는 직접 입력)를 넘긴 뒤 다음 단계로 진행
  final void Function(String selectedReasonText) onContinueWithReason;
  final int step;
  final int totalSteps;

  const Screen3Reasons({
    super.key,
    required this.onContinueWithReason,
    this.step = 3,
    this.totalSteps = 9,
  });

  static const String kOtherChoice = '__OTHER__';

  @override
  State<Screen3Reasons> createState() => _Screen3ReasonsState();
}

class _Screen3ReasonsState extends State<Screen3Reasons> {
  final List<String> _presets = [
    '건강 회복을 위해',
    '가족을 위해',
    '경제적 절약',
    '나를 위한 자기관리',
    '습관 개선',
  ];

  /// 프리셋 문자열 또는 [Screen3Reasons.kOtherChoice]
  String? _choice;
  final TextEditingController _otherController = TextEditingController();

  static const int _maxReasonLen = 120;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String? get _effectiveReason {
    if (_choice == null) return null;
    if (_choice == Screen3Reasons.kOtherChoice) {
      final t = _otherController.text.trim();
      if (t.isEmpty) return null;
      if (t.length > _maxReasonLen) return t.substring(0, _maxReasonLen);
      return t;
    }
    return _choice;
  }

  bool get _canContinue => _effectiveReason != null;

  void _onContinue() {
    final r = _effectiveReason;
    if (r == null) return;
    widget.onContinueWithReason(r);
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
                '금연을 결심한 이유는\n무엇인가요?',
                style: OnboardingTheme.headline,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  ..._presets.map((reason) {
                    final isSelected = _choice == reason;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _choice = reason),
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
                  }),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _choice = Screen3Reasons.kOtherChoice),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          decoration: OnboardingTheme.optionCardDecoration(
                            selected: _choice == Screen3Reasons.kOtherChoice,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _choice == Screen3Reasons.kOtherChoice
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: _choice == Screen3Reasons.kOtherChoice ? AppTheme.primary : AppTheme.textMuted,
                                size: 24,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  '기타 (직접 입력)',
                                  style: OnboardingTheme.bodyBold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_choice == Screen3Reasons.kOtherChoice) ...[
                    TextField(
                      controller: _otherController,
                      maxLength: _maxReasonLen,
                      maxLines: 3,
                      minLines: 2,
                      decoration: InputDecoration(
                        hintText: '금연을 결심한 이유를 적어주세요',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_otherController.text.length.clamp(0, _maxReasonLen)} / $_maxReasonLen',
                      style: OnboardingTheme.body.copyWith(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _canContinue ? _onContinue : null,
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
