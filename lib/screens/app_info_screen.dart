import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../auth/legal_urls.dart';
import '../theme/app_theme.dart';

/// 앱 정보 화면 (버전 자동 동기화, 이메일 문의 포함)
class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {

  static const String _email = 'cjw207207@gmail.com';
  /// `PackageInfo.version` (사용자에게 보이는 버전 이름만 표시)
  String _versionLine = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLine = '버전 ${info.version}';
      });
    } catch (_) {
      // 실패 시 빈 문자열 유지
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri.parse('mailto:$_email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일 앱을 열 수 없습니다.')),
        );
      }
    }
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(LegalUrls.privacyPolicy);
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

  Future<void> _openTermsOfService(BuildContext context) async {
    final uri = Uri.parse(LegalUrls.termsOfService);
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

  Future<void> _openSensitiveInfoConsent(BuildContext context) async {
    final uri = Uri.parse(LegalUrls.sensitiveInfoConsent);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('앱 정보'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(Icons.eco_rounded, size: 72, color: AppTheme.primary),
                const SizedBox(height: 16),
                Text('금연뱅크', style: AppTheme.titleLarge.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                  _versionLine.isEmpty ? '버전 정보를 불러오는 중입니다...' : _versionLine,
                  style: AppTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _sectionTitle('문의하기'),
          _infoTile(
            context,
            icon: Icons.email_rounded,
            title: '이메일 문의',
            subtitle: _email,
            onTap: () => _launchEmail(context),
          ),
          _infoTile(
            context,
            icon: Icons.shield_rounded,
            title: '개인정보처리방침',
            subtitle: '개인정보 처리 방침 보기',
            onTap: () => _openPrivacyPolicy(context),
          ),
          _infoTile(
            context,
            icon: Icons.description_rounded,
            title: '이용약관',
            subtitle: '서비스 이용약관 보기',
            onTap: () => _openTermsOfService(context),
          ),
          _infoTile(
            context,
            icon: Icons.health_and_safety_rounded,
            title: '민감정보 수집·이용 동의',
            subtitle: '흡연·금연 관련 정보 수집·이용 안내 보기',
            onTap: () => _openSensitiveInfoConsent(context),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '금연을 응원합니다.',
              style: AppTheme.labelMedium.copyWith(color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: AppTheme.labelMedium.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primary, size: 24),
        title: Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 16)),
        subtitle: Text(subtitle, style: AppTheme.bodyMedium),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
