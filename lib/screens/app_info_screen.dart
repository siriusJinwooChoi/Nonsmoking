import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// 앱 정보 화면 (View licenses 없음, 이메일 문의 포함)
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  static const String _email = 'cjw207207@gmail.com';
  static const String _version = '1.0.0';

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
                Text('금연', style: AppTheme.titleLarge.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text('버전 $_version', style: AppTheme.bodyMedium),
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
