import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/bff_profile_api.dart';
import '../supabase/supabase_config.dart';
import '../theme/app_theme.dart';
import 'legal_consent_versions.dart';
import 'terms_detail_actions.dart';

/// 서비스 이용 필수 동의 (참고 UI: 체크리스트 + 하단 검정 버튼).
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({super.key, required this.onAgreed});

  final VoidCallback onAgreed;

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _t1 = false;
  bool _t2 = false;
  bool _t3 = false;
  bool _t4 = false;
  bool _busy = false;

  bool get _all => _t1 && _t2 && _t3 && _t4;

  Future<void> _submit() async {
    if (!_all || _busy) return;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kTermsAgreedPrefsKey, true);

      if (SupabaseConfig.isConfigured) {
        // 모든 동의(이용약관·개인정보·민감정보·만 14세)는 한 화면에서 동시에 체크되므로
        // 동일한 acceptedAt 으로 묶어 BFF에 일괄 저장한다.
        final acceptedAt = DateTime.now().toUtc().toIso8601String();
        await BffProfileApi.patchProfile(
          termsAcceptedAtIso: acceptedAt,
          termsOfServiceAcceptedAtIso: acceptedAt,
          termsOfServiceVersion: LegalConsentVersions.termsOfService,
          privacyPolicyAcceptedAtIso: acceptedAt,
          privacyPolicyVersion: LegalConsentVersions.privacyPolicy,
          sensitiveInfoConsentAtIso: acceptedAt,
          sensitiveInfoConsentVersion: LegalConsentVersions.sensitiveInfoConsent,
          ageConfirmedAtIso: acceptedAt,
        );
      }

      widget.onAgreed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1A3A52);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              '금연뱅크',
              style: GoogleFonts.notoSansKr(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '서비스 이용 전 동의가 필요해요',
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        '서비스 이용 필수 동의',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _tile(
                            '이용 약관 동의',
                            _t1,
                            (v) => setState(() => _t1 = v),
                            TermsDetailActions.openTermsOfService,
                          ),
                          _tile(
                            '개인정보 수집 및 이용 동의',
                            _t2,
                            (v) => setState(() => _t2 = v),
                            TermsDetailActions.openPrivacyPolicy,
                          ),
                          _tile(
                            '민감정보 수집 및 이용 동의',
                            _t3,
                            (v) => setState(() => _t3 = v),
                            TermsDetailActions.openSensitiveInfoNotice,
                          ),
                          _tile(
                            '만 14세 이상입니다',
                            _t4,
                            (v) => setState(() => _t4 = v),
                            TermsDetailActions.openAgeNotice,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _all && !_busy ? _submit : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.black87,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  '네, 모두 동의해요',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
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

  Widget _tile(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    Future<void> Function(BuildContext context) onOpenDetail,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(!value),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        value ? Icons.check_circle : Icons.circle_outlined,
                        color: value ? AppTheme.primary : AppTheme.textMuted,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '내용 보기',
              visualDensity: VisualDensity.compact,
              onPressed: () => onOpenDetail(context),
              icon: Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
