import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notifications/daily_reminder_worker.dart';
import '../theme/app_theme.dart';

/// 알림을 여러 개 추가/삭제할 수 있는 화면
class ReminderSettingsScreen extends StatefulWidget {
  final List<TimeOfDay> initialTimes;
  final void Function(List<TimeOfDay>) onUpdated;

  const ReminderSettingsScreen({
    super.key,
    required this.initialTimes,
    required this.onUpdated,
  });

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  late List<TimeOfDay> _times;

  @override
  void initState() {
    super.initState();
    _times = List.from(widget.initialTimes);
  }

  Future<void> _addReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _times.add(picked);
      _times.sort((a, b) {
        final amin = a.hour * 60 + a.minute;
        final bmin = b.hour * 60 + b.minute;
        return amin.compareTo(bmin);
      });
    });
    await saveReminderTimes(_times);
    widget.onUpdated(List.from(_times));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('매일 ${picked.format(context)}에 알림이 추가되었습니다.'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _removeAt(int index) async {
    setState(() => _times.removeAt(index));
    await saveReminderTimes(_times);
    widget.onUpdated(List.from(_times));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림이 삭제되었습니다.'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _editAt(int index) async {
    final t = _times[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: t,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _times[index] = picked;
      _times.sort((a, b) {
        final amin = a.hour * 60 + a.minute;
        final bmin = b.hour * 60 + b.minute;
        return amin.compareTo(bmin);
      });
    });
    await saveReminderTimes(_times);
    widget.onUpdated(List.from(_times));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('매일 ${picked.format(context)}로 변경되었습니다.'), duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('알림 설정'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          Text(
            '설정한 시간마다 금연 리마인더 알림이 옵니다. 여러 개 추가할 수 있습니다.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          if (_times.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 56, color: AppTheme.textMuted),
                    const SizedBox(height: 12),
                    Text('등록된 알림이 없습니다.', style: AppTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '아래 + 버튼으로 알림 시간을 추가하세요.',
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_times.length, (i) {
              final t = _times[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppTheme.cardShadowSubtle,
                ),
                child: ListTile(
                  leading: Icon(Icons.schedule_rounded, color: AppTheme.primary),
                  title: Text('매일 ${t.format(context)}', style: AppTheme.titleMedium),
                  subtitle: const Text('탭하면 시간 변경', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  onTap: () => _editAt(i),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.error),
                    onPressed: () => _removeAt(i),
                    tooltip: '삭제',
                  ),
                ),
              );
            }),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReminder,
        child: const Icon(Icons.add_rounded),
        tooltip: '알림 추가',
      ),
    );
  }
}
