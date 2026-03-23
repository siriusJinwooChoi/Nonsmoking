import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'legal_urls.dart';

/// 필수 동의 항목별 «내용 보기» (외부 문서 또는 안내 다이얼로그)
abstract final class TermsDetailActions {
  static Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 열 수 없습니다.')),
        );
      }
    }
  }

  static Future<void> openTermsOfService(BuildContext context) =>
      _launch(context, LegalUrls.termsOfService);

  static Future<void> openPrivacyPolicy(BuildContext context) =>
      _launch(context, LegalUrls.privacyPolicy);

  static Future<void> openSensitiveInfoNotice(BuildContext context) =>
      _launch(context, LegalUrls.sensitiveInfoConsent);

  static Future<void> openAgeNotice(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '만 14세 이상 이용',
          style: GoogleFonts.notoSansKr(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        content: Text(
          '본 서비스는 만 14세 미만 아동을 대상으로 하지 않으며, '
          '만 14세 이상만 가입·이용할 수 있습니다. '
          '동의 시 본인이 만 14세 이상임을 확인한 것으로 간주됩니다.',
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            height: 1.55,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '확인',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
