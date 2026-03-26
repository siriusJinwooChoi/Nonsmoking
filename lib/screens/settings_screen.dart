import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_service.dart';
import '../auth/legal_urls.dart';
import '../supabase/supabase_config.dart';
import '../supabase/supabase_sync_service.dart';
import '../theme/app_theme.dart';
import '../notifications/daily_reminder_worker.dart';
import 'app_info_screen.dart';
import 'help_screen.dart';
import 'badge_screen.dart';
import 'reminder_settings_screen.dart';

/// 설정 화면: 알림, 초기 설정으로 돌아가기, 앱 정보
class SettingsScreen extends StatefulWidget {
  final List<TimeOfDay> reminderTimes;
  final void Function(List<TimeOfDay>) onReminderUpdated;
  final Future<void> Function() onGoToFirstSetup;

  const SettingsScreen({
    super.key,
    required this.reminderTimes,
    required this.onReminderUpdated,
    required this.onGoToFirstSetup,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _inactivityNotificationEnabled = true;
  bool _attendanceReminderEnabled = true;
  bool _cigaretteCollectionReminderEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadInactivitySetting();
    _loadAttendanceReminderSetting();
    _loadCigaretteCollectionReminderSetting();
  }

  Future<void> _loadInactivitySetting() async {
    final v = await getInactivityNotificationEnabled();
    if (mounted) setState(() => _inactivityNotificationEnabled = v);
  }

  Future<void> _loadAttendanceReminderSetting() async {
    final v = await getAttendanceReminderEnabled();
    if (mounted) setState(() => _attendanceReminderEnabled = v);
  }

  Future<void> _loadCigaretteCollectionReminderSetting() async {
    final v = await getCigaretteCollectionReminderEnabled();
    if (mounted) setState(() => _cigaretteCollectionReminderEnabled = v);
  }

  Widget _inactivityNotificationTile(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: const Icon(Icons.notifications_active_rounded, color: AppTheme.primary, size: 24),
        title: Text(
          '비접속 시 알림',
          style: AppTheme.titleMedium.copyWith(fontSize: 16, color: AppTheme.textPrimary),
        ),
        subtitle: const Text(
          '3일 이상 앱을 열지 않으면 매일 알림',
          style: AppTheme.bodyMedium,
        ),
        trailing: Switch(
          value: _inactivityNotificationEnabled,
          onChanged: (value) async {
            await setInactivityNotificationEnabled(value);
            if (!context.mounted) return;
            setState(() => _inactivityNotificationEnabled = value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(value ? '비접속 시 알림을 켰습니다.' : '비접속 시 알림을 껐습니다.'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          activeThumbColor: AppTheme.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _attendanceReminderTile(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: const Icon(Icons.today_rounded, color: AppTheme.primary, size: 24),
        title: Text(
          '출석 알림',
          style: AppTheme.titleMedium.copyWith(fontSize: 16, color: AppTheme.textPrimary),
        ),
        subtitle: const Text(
          '저녁 6시까지 미출석 시 10분마다 알림',
          style: AppTheme.bodyMedium,
        ),
        trailing: Switch(
          value: _attendanceReminderEnabled,
          onChanged: (value) async {
            await setAttendanceReminderEnabled(value);
            if (!context.mounted) return;
            setState(() => _attendanceReminderEnabled = value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(value ? '출석 알림을 켰습니다.' : '출석 알림을 껐습니다.'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          activeThumbColor: AppTheme.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Widget _cigaretteCollectionReminderTile(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 24),
        title: Text(
          '담배 수집 알림',
          style: AppTheme.titleMedium.copyWith(fontSize: 16, color: AppTheme.textPrimary),
        ),
        subtitle: const Text(
          '09:00·12:00·18:00·22:00 정각에 수집 가능 시간 안내',
          style: AppTheme.bodyMedium,
        ),
        trailing: Switch(
          value: _cigaretteCollectionReminderEnabled,
          onChanged: (value) async {
            await setCigaretteCollectionReminderEnabled(value);
            if (!context.mounted) return;
            setState(() => _cigaretteCollectionReminderEnabled = value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(value ? '담배 수집 알림을 켰습니다.' : '담배 수집 알림을 껐습니다.'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          activeThumbColor: AppTheme.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Future<void> _openReminderSettings(BuildContext context, List<TimeOfDay> reminderTimes, void Function(List<TimeOfDay>) onReminderUpdated) async {
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
      await widget.onGoToFirstSetup();
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
            subtitle: widget.reminderTimes.isEmpty
                ? '알림 없음'
                : '${widget.reminderTimes.length}개 설정됨',
            onTap: () => _openReminderSettings(context, widget.reminderTimes, widget.onReminderUpdated),
          ),
          _inactivityNotificationTile(context),
          _attendanceReminderTile(context),
          _cigaretteCollectionReminderTile(context),
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
          if (SupabaseConfig.isConfigured) ...[
            const SizedBox(height: 24),
            _sectionTitle('계정'),
            _settingsTile(
              context,
              icon: Icons.logout_rounded,
              title: '로그아웃',
              subtitle: '이 기기에서 로그아웃 합니다.',
              titleColor: AppTheme.error,
              onTap: () => _confirmSignOut(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('로그아웃'),
        content: const Text('로그아웃하면 이 계정으로 동기화된 데이터는 다음 로그인 때 다시 불러올 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    await AuthService.signOut();
    if (!context.mounted) return;
    // 설정 화면이 스택에 남아 로그인 화면이 가려지는 것을 방지 (AuthGate는 세션만 없애고 라우트는 유지될 수 있음)
    Navigator.of(context).popUntil((route) => route.isFirst);
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
