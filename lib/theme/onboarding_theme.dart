import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// 번핏 스타일 온보딩 공통 스타일·위젯
class OnboardingTheme {
  OnboardingTheme._();

  static const int totalSteps = 9;
  static const Color pageBackground = Colors.white;
  static const Color progressBg = Color(0xFFE5E7EB);
  static Color get progressFill => AppTheme.primary;

  static TextStyle get headline => GoogleFonts.notoSansKr(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: const Color(0xFF1F2937),
    height: 1.4,
  );

  static TextStyle get headlineSub => GoogleFonts.notoSansKr(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF4B5563),
    height: 1.4,
  );

  static TextStyle get body => GoogleFonts.notoSansKr(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: const Color(0xFF4B5563),
    height: 1.5,
  );

  static TextStyle get bodyBold => GoogleFonts.notoSansKr(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: const Color(0xFF1F2937),
    height: 1.5,
  );

  static TextStyle get button => GoogleFonts.notoSansKr(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  /// 상단 진행률 바 (번핏 스타일)
  static Widget progressBar(int step, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? (step / total) : 0,
              minHeight: 4,
              backgroundColor: progressBg,
              valueColor: AlwaysStoppedAnimation<Color>(progressFill),
            ),
          ),
        ],
      ),
    );
  }

  /// 메인 CTA 버튼
  static Widget primaryButton({
    required VoidCallback onPressed,
    required String label,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Text(label, style: button),
      ),
    );
  }

  /// 선택 카드 (라디오/리스트용)
  static BoxDecoration optionCardDecoration({bool selected = false}) {
    return BoxDecoration(
      color: selected ? AppTheme.primary.withOpacity(0.08) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: selected ? AppTheme.primary : const Color(0xFFE5E7EB),
        width: selected ? 2 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// 입력칸 하나로 통일 - 테두리와 포커스 강조가 같은 칸에 맞게 적용
  static const double inputBorderRadius = 14;
  static InputDecoration inputDecoration({
    required String labelText,
    required String hintText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputBorderRadius),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputBorderRadius),
      borderSide: const BorderSide(color: AppTheme.primary, width: 2),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(inputBorderRadius),
        borderSide: const BorderSide(color: AppTheme.error),
      ),
    );
  }
}
