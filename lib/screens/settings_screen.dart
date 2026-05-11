import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_nav.dart';
import '../auth/auth_service.dart';
import '../auth/bff_auth_service.dart';
import '../api/bff_profile_api.dart';
import '../services/app_update_service.dart';
import '../supabase/supabase_config.dart';
import '../supabase/supabase_sync_service.dart';
import '../theme/app_theme.dart';
import '../notifications/daily_reminder_worker.dart';
import 'app_info_screen.dart';
import 'help_screen.dart';
import 'badge_screen.dart';
import 'notification_opt_out_screen.dart';
import 'reminder_settings_screen.dart';

/// 설정 화면: 알림, 초기 설정으로 돌아가기, 앱 정보
class SettingsScreen extends StatefulWidget {
  final List<TimeOfDay> reminderTimes;
  final void Function(List<TimeOfDay>) onReminderUpdated;
  final Future<void> Function() onGoToFirstSetup;
  final Future<void> Function()? onShowTutorial;

  const SettingsScreen({
    super.key,
    required this.reminderTimes,
    required this.onReminderUpdated,
    required this.onGoToFirstSetup,
    this.onShowTutorial,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _inactivityNotificationEnabled = true;
  bool _attendanceReminderEnabled = true;
  bool _cigaretteCollectionReminderEnabled = true;
  bool _patternReminderEnabled = true;
  late List<TimeOfDay> _reminderTimes;
  String? _displayName;
  bool _savingDisplayName = false;

  @override
  void initState() {
    super.initState();
    _reminderTimes = List<TimeOfDay>.from(widget.reminderTimes);
    _loadInactivitySetting();
    _loadAttendanceReminderSetting();
    _loadCigaretteCollectionReminderSetting();
    _loadPatternReminderSetting();
    unawaited(_loadDisplayName());
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reminderTimes != widget.reminderTimes) {
      _reminderTimes = List<TimeOfDay>.from(widget.reminderTimes);
    }
  }

  void _applyReminderTimes(List<TimeOfDay> times) {
    if (!mounted) return;
    setState(() => _reminderTimes = List<TimeOfDay>.from(times));
    widget.onReminderUpdated(List<TimeOfDay>.from(times));
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

  Future<void> _loadPatternReminderSetting() async {
    final v = await getPatternReminderEnabled();
    if (mounted) setState(() => _patternReminderEnabled = v);
  }

  Future<void> _loadDisplayName() async {
    if (!BffAuthService.instance.isLoggedIn) return;
    final cached = await BffProfileApi.readCachedDisplayNameForCurrentUser();
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() => _displayName = cached);
    }

    final row = await BffProfileApi.fetchProfile();
    if (!mounted || row == null) return;
    final name = (row['display_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      await BffProfileApi.cacheDisplayNameForCurrentUser(name);
      if (mounted) setState(() => _displayName = name);
    }
  }

  Future<void> _editDisplayName() async {
    if (!BffAuthService.instance.isLoggedIn) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _NicknameEditDialog(initialValue: _displayName ?? ''),
    );

    if (result == null || result.trim().isEmpty) return;
    if (result.trim() == (_displayName ?? '').trim()) return;

    setState(() => _savingDisplayName = true);
    final ok = await BffProfileApi.patchProfile(displayName: result.trim());
    if (!mounted) return;
    setState(() => _savingDisplayName = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임 저장에 실패했습니다. 잠시 후 다시 시도해 주세요.')),
      );
      return;
    }

    await BffProfileApi.cacheDisplayNameForCurrentUser(result.trim());
    if (!mounted) return;
    setState(() => _displayName = result.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('닉네임을 변경했습니다.')),
    );
  }

  Future<void> _setInactivityNotification(bool value) async {
    if (!mounted) return;
    setState(() => _inactivityNotificationEnabled = value);
    await setInactivityNotificationEnabled(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '비접속 시 알림을 켰습니다.' : '비접속 시 알림을 껐습니다.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _setAttendanceReminder(bool value) async {
    if (!mounted) return;
    setState(() => _attendanceReminderEnabled = value);
    await setAttendanceReminderEnabled(value);
    if (!mounted) return;
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '출석 알림을 켰습니다.' : '출석 알림을 껐습니다.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _setCigaretteCollectionReminder(bool value) async {
    if (!mounted) return;
    setState(() => _cigaretteCollectionReminderEnabled = value);
    await setCigaretteCollectionReminderEnabled(value);
    if (!mounted) return;
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '수집 시간 알림을 켰습니다.' : '수집 시간 알림을 껐습니다.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _setPatternReminder(bool value) async {
    if (!mounted) return;
    setState(() => _patternReminderEnabled = value);
    await setPatternReminderEnabled(value);
    if (!mounted) return;
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '패턴 기반 자동 알림을 켰습니다.' : '패턴 기반 자동 알림을 해지했습니다.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openReminderSettings(BuildContext context) async {
    final result = await Navigator.push<List<TimeOfDay>>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderSettingsScreen(
          initialTimes: List.from(_reminderTimes),
          onUpdated: _applyReminderTimes,
        ),
      ),
    );
    if (result != null) {
      _applyReminderTimes(result);
      return;
    }
    final fresh = await getReminderTimes();
    _applyReminderTimes(fresh);
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

  Future<void> _checkForAppUpdate(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final info = await PackageInfo.fromPlatform();
      final store = await fetchPlayStoreLatestVersionName();
      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (store == null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('업데이트 확인'),
            content: Text(
              'Play 스토어는 페이지 구조·보안 정책 때문에 앱에서 자동으로 최신 버전 숫자를 읽기 어려울 수 있습니다.\n\n'
              '스토어에서 직접 업데이트 여부를 확인하거나, 잠시 후 다시 시도해 주세요.\n\n'
              '이 기기 앱 버전: ${info.version}',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await openPlayStoreAppPage();
                },
                child: const Text('스토어 열기'),
              ),
            ],
          ),
        );
        return;
      }

      if (isInstalledOlderThanStore(info.version, store)) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('새 버전이 있습니다'),
            content: Text(
              '스토어 최신 버전: $store\n'
              '이 기기 버전: ${info.version}\n\n'
              '스토어에서 업데이트할 수 있습니다.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('닫기')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('스토어로 이동')),
            ],
          ),
        );
        if (go == true && context.mounted) await openPlayStoreAppPage();
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('업데이트 확인'),
            content: Text('현재 버전(${info.version})이 최신입니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
            ],
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업데이트 확인 중 오류가 발생했습니다.')),
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
            subtitle: '넘긴 개비·금연 일수 뱃지 확인',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BadgeScreen()),
              );
            },
          ),
          const SizedBox(height: 24),
          _sectionTitle('일반'),
          if (SupabaseConfig.isConfigured && BffAuthService.instance.isLoggedIn)
            _settingsTile(
              context,
              icon: Icons.badge_rounded,
              title: '닉네임 변경',
              subtitle: _savingDisplayName
                  ? '저장 중...'
                  : ((_displayName == null || _displayName!.isEmpty)
                        ? '현재 닉네임 없음'
                        : '현재: $_displayName'),
              onTap: _savingDisplayName ? () {} : _editDisplayName,
            ),
          _settingsTile(
            context,
            icon: Icons.notifications_rounded,
            title: '알림',
            subtitle: _reminderTimes.isEmpty
                ? '알림 없음'
                : '${_reminderTimes.length}개 설정됨',
            onTap: () => _openReminderSettings(context),
          ),
          _settingsTile(
            context,
            icon: Icons.notifications_off_rounded,
            title: '알림 해지',
            subtitle: '비접속·출석·수집 시간 알림 설정',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationOptOutScreen(
                    inactivityNotificationEnabled: _inactivityNotificationEnabled,
                    attendanceReminderEnabled: _attendanceReminderEnabled,
                    cigaretteCollectionReminderEnabled: _cigaretteCollectionReminderEnabled,
                    patternReminderEnabled: _patternReminderEnabled,
                    onInactivityChanged: _setInactivityNotification,
                    onAttendanceChanged: _setAttendanceReminder,
                    onCigaretteCollectionChanged: _setCigaretteCollectionReminder,
                    onPatternReminderChanged: _setPatternReminder,
                  ),
                ),
              );
            },
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
            icon: Icons.play_circle_outline_rounded,
            title: '튜토리얼 보기',
            subtitle: '메인 화면 튜토리얼 다시 보기',
            onTap: () async {
              await widget.onShowTutorial?.call();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
          _settingsTile(
            context,
            icon: Icons.system_update_rounded,
            title: '업데이트 확인',
            subtitle: 'Play 스토어 최신 버전과 비교',
            onTap: () => _checkForAppUpdate(context),
          ),
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
            _settingsTile(
              context,
              icon: Icons.person_remove_alt_1_rounded,
              title: '계정 삭제',
              subtitle: '계정 및 동기화 데이터를 삭제합니다.',
              titleColor: AppTheme.error,
              onTap: _confirmDeleteAccount,
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
    // 로그아웃 직전 동기화를 명시적으로 완료해 데이터 유실/경합을 방지한다.
    await SupabaseSyncService.pushLocalToRemoteIfEligible();
    await AuthService.signOut();
    if (!context.mounted) return;
    await _returnToAuthGateRoot();
  }

  Future<void> _confirmDeleteAccount() async {
    final email = BffAuthService.instance.userEmail?.trim();
    final target =
        (email != null && email.isNotEmpty) ? email : '현재 로그인된 계정';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('계정 삭제'),
        content: Text(
          '삭제 대상: $target\n\n'
          '계정을 삭제하면 서버에 저장된 계정 및 동기화 데이터가 삭제되며 복구할 수 없습니다.\n\n'
          '정말 계정을 삭제하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('계정 삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await AuthService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      // 세션은 이미 끊김 — 설정·그 위 푸시 스택을 먼저 비워야 AuthGate 아래 로그인 화면이 보임
      await _returnToAuthGateRoot();
      final rootCtx = appRootNavigatorKey.currentContext;
      if (rootCtx != null && rootCtx.mounted) {
        ScaffoldMessenger.of(rootCtx).showSnackBar(
          const SnackBar(content: Text('계정이 삭제되었습니다.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정 삭제에 실패했습니다. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  /// 로그아웃/계정삭제 후 [AuthGate]가 있는 루트로 돌아가 세션 변화를 반영한다.
  /// `LoginScreen`만 단독으로 쌓으면 OAuth 복귀 후에도 화면이 갱신되지 않는다.
  Future<void> _returnToAuthGateRoot() async {
    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
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

class _NicknameEditDialog extends StatefulWidget {
  final String initialValue;

  const _NicknameEditDialog({required this.initialValue});

  @override
  State<_NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<_NicknameEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.length < 2 || v.length > 12) {
      setState(() => _errorText = '닉네임은 2~12자로 입력해 주세요.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('닉네임 변경'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            maxLength: 12,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '닉네임',
              hintText: '2~12자',
              counterText: '',
              errorText: _errorText,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
