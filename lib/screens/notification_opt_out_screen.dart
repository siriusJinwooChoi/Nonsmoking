import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NotificationOptOutScreen extends StatefulWidget {
  final bool inactivityNotificationEnabled;
  final bool attendanceReminderEnabled;
  final bool cigaretteCollectionReminderEnabled;
  final Future<void> Function(bool value) onInactivityChanged;
  final Future<void> Function(bool value) onAttendanceChanged;
  final Future<void> Function(bool value) onCigaretteCollectionChanged;

  const NotificationOptOutScreen({
    super.key,
    required this.inactivityNotificationEnabled,
    required this.attendanceReminderEnabled,
    required this.cigaretteCollectionReminderEnabled,
    required this.onInactivityChanged,
    required this.onAttendanceChanged,
    required this.onCigaretteCollectionChanged,
  });

  @override
  State<NotificationOptOutScreen> createState() => _NotificationOptOutScreenState();
}

class _NotificationOptOutScreenState extends State<NotificationOptOutScreen> {
  late bool _inactivityNotificationEnabled;
  late bool _attendanceReminderEnabled;
  late bool _cigaretteCollectionReminderEnabled;

  @override
  void initState() {
    super.initState();
    _inactivityNotificationEnabled = widget.inactivityNotificationEnabled;
    _attendanceReminderEnabled = widget.attendanceReminderEnabled;
    _cigaretteCollectionReminderEnabled = widget.cigaretteCollectionReminderEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('알림 해지'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: 12,
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          _switchTile(
            icon: Icons.notifications_active_rounded,
            title: '비접속 시 알림',
            subtitle: '3일 이상 앱을 열지 않으면 매일 알림',
            value: _inactivityNotificationEnabled,
            onChanged: (value) async {
              setState(() => _inactivityNotificationEnabled = value);
              await widget.onInactivityChanged(value);
            },
          ),
          _switchTile(
            icon: Icons.today_rounded,
            title: '출석 알림',
            subtitle: '저녁 6시까지 미출석 시 1시간마다 알림',
            value: _attendanceReminderEnabled,
            onChanged: (value) async {
              setState(() => _attendanceReminderEnabled = value);
              await widget.onAttendanceChanged(value);
            },
          ),
          _switchTile(
            icon: Icons.inventory_2_rounded,
            title: '수집 시간 알림',
            subtitle: '09:00·12:00·18:00·22:00 정각에 도감 수집 가능 안내',
            value: _cigaretteCollectionReminderEnabled,
            onChanged: (value) async {
              setState(() => _cigaretteCollectionReminderEnabled = value);
              await widget.onCigaretteCollectionChanged(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool value) onChanged,
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
        title: Text(
          title,
          style: AppTheme.titleMedium.copyWith(fontSize: 16, color: AppTheme.textPrimary),
        ),
        subtitle: Text(
          subtitle,
          style: AppTheme.bodyMedium,
        ),
        trailing: Switch(
          value: value,
          onChanged: (next) {
            onChanged(next);
          },
          activeThumbColor: AppTheme.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
