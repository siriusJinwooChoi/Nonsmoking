import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'app_info_screen.dart';
import 'help_screen.dart';
import 'badge_screen.dart';
import 'reminder_settings_screen.dart';

/// 설정 화면: 알림, 초기 설정으로 돌아가기, 앱 정보
class SettingsScreen extends StatelessWidget {
  final List<TimeOfDay> reminderTimes;
  final void Function(List<TimeOfDay>) onReminderUpdated;
  final Future<void> Function() onGoToFirstSetup;

  const SettingsScreen({
    super.key,
    required this.reminderTimes,
    required this.onReminderUpdated,
    required this.onGoToFirstSetup,
  });

  Future<void> _openReminderSettings(BuildContext context) async {
    final updated = await Navigator.push<List<TimeOfDay>>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderSettingsScreen(
          initialTimes: List.from(reminderTimes),
          onUpdated: onReminderUpdated,
        ),
      ),
    );
    if (updated != null) onReminderUpdated(updated);
  }

  Future<void> _confirmGoToFirstSetup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('처음 설정으로 돌아가기'),
        content: const Text(
          '처음 설정 화면으로 돌아가시겠습니까?\n\n'
          '입력한 설정(흡연량/가격 등)과 진행 기록이 초기화될 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onGoToFirstSetup();
    }
  }

  static const String _privacyPolicyUrl = 'https://www.notion.so/29f5de29af9680c0b7a1d2b2762777e8';
  static const String _termsOfServiceUrl = 'https://www.notion.so/31e5de29af9680d6aa8af96ef24a4410';

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(_privacyPolicyUrl);
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
    final uri = Uri.parse(_termsOfServiceUrl);
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
        title: const Text('설정'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: 12,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 48,
        ),
        children: [
          const SizedBox(height: 8),
          _sectionTitle('관리'),
          _settingsTile(
            context,
            icon: Icons.emoji_events_rounded,
            title: '금연 뱃지',
            subtitle: '피우지 않은 담배·금연 일수 뱃지 확인',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BadgeScreen()),
              );
            },
          ),
          const SizedBox(height: 24),
          _sectionTitle('일반'),
          _settingsTile(
            context,
            icon: Icons.notifications_rounded,
            title: '알림',
            subtitle: reminderTimes.isEmpty
                ? '알림 없음'
                : '${reminderTimes.length}개 설정됨',
            onTap: () => _openReminderSettings(context),
          ),
          const SizedBox(height: 24),
          _sectionTitle('데이터'),
          _settingsTile(
            context,
            icon: Icons.restart_alt_rounded,
            title: '초기 설정으로 돌아가기',
            subtitle: '흡연량·가격 등 처음부터 다시 설정',
            onTap: () => _confirmGoToFirstSetup(context),
            titleColor: AppTheme.warning,
          ),
          const SizedBox(height: 24),
          _sectionTitle('설정'),
          _settingsTile(
            context,
            icon: Icons.info_outline_rounded,
            title: '앱 정보',
            subtitle: '버전 정보 및 이메일 문의',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppInfoScreen()),
              );
            },
          ),
          _settingsTile(
            context,
            icon: Icons.help_outline_rounded,
            title: '도움말',
            subtitle: '사용법 및 자주 묻는 질문',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),
          _settingsTile(
            context,
            icon: Icons.shield_rounded,
            title: '개인정보처리방침',
            subtitle: '개인정보 처리 방침 보기',
            onTap: () => _openPrivacyPolicy(context),
          ),
          _settingsTile(
            context,
            icon: Icons.description_rounded,
            title: '이용약관',
            subtitle: '서비스 이용약관 보기',
            onTap: () => _openTermsOfService(context),
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

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: Icon(icon, color: titleColor ?? AppTheme.primary, size: 24),
        title: Text(
          title,
          style: AppTheme.titleMedium.copyWith(
            fontSize: 16,
            color: titleColor ?? AppTheme.textPrimary,
          ),
        ),
        subtitle: Text(subtitle, style: AppTheme.bodyMedium),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
