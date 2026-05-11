import 'dart:async';

import 'package:flutter/material.dart';
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

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen>
    with SingleTickerProviderStateMixin {
  late List<TimeOfDay> _times;
  List<TimeOfDay> _patternTimes = const [];
  bool _hasLocalEdits = false;
  int _selectedTab = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted && _selectedTab != _tabController.index) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    _times = List.from(widget.initialTimes);
    unawaited(_reloadTimesFromPrefs());
    unawaited(_reloadPatternTimesFromPrefs());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 부모가 넘긴 목록은 첫 프레임용이며, 저장소와 동기화해 재진입 시에도 최신 목록을 보여준다.
  Future<void> _reloadTimesFromPrefs() async {
    final t = await getReminderTimes();
    if (!mounted) return;
    // 화면 진입 직후 비동기 로드가 늦게 도착해도,
    // 사용자가 이미 추가/수정/삭제한 로컬 상태를 덮어쓰지 않도록 보호한다.
    if (_hasLocalEdits) return;
    setState(() {
      _times = t;
      _sortTimes();
    });
  }

  Future<void> _reloadPatternTimesFromPrefs() async {
    final times = await getPatternReminderSlots();
    if (!mounted) return;
    setState(() {
      _patternTimes = List<TimeOfDay>.from(times)
        ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    });
  }

  void _sortTimes() {
    _times.sort((a, b) {
      final amin = a.hour * 60 + a.minute;
      final bmin = b.hour * 60 + b.minute;
      return amin.compareTo(bmin);
    });
  }

  Future<void> _persistAndNotify() async {
    await saveReminderTimes(_times);
    if (!mounted) return;
    widget.onUpdated(List.from(_times));
  }

  Future<void> _addReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _hasLocalEdits = true;
      _times.add(picked);
      _sortTimes();
    });
    await _persistAndNotify();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('매일 ${picked.format(context)}에 알림이 추가되었습니다.'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _removeAt(int index) async {
    setState(() {
      _hasLocalEdits = true;
      _times.removeAt(index);
    });
    await _persistAndNotify();
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
      _hasLocalEdits = true;
      _times[index] = picked;
      _sortTimes();
    });
    await _persistAndNotify();
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, List<TimeOfDay>.from(_times)),
        ),
      ),
      body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(text: '사용자 설정 알림'),
                        Tab(text: '패턴 알림'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      ListView(
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
                                      '오른쪽 아래 + 버튼으로 알림 시간을 추가하세요.',
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
                      ListView(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                          bottom: MediaQuery.of(context).padding.bottom + 24,
                        ),
                        children: [
                          Text(
                            '방금 피움 기록을 분석해 자동으로 생성되는 예방 알림 시간대입니다.',
                            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 10),
                          if (_patternTimes.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceCard,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '아직 생성된 패턴 알림이 없습니다.\n방금 피움 기록 5건 이상부터 자동 생성됩니다.',
                                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                              ),
                            )
                          else
                            ...List.generate(_patternTimes.length, (i) {
                              final t = _patternTimes[i];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceCard,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: AppTheme.cardShadowSubtle,
                                ),
                                child: ListTile(
                                  leading: Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
                                  title: Text('매일 ${t.format(context)} (3분 전 발송)', style: AppTheme.titleMedium),
                                  subtitle: const Text(
                                    '자동 생성된 패턴 알림 (직접 수정 불가)',
                                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton(
              onPressed: _addReminder,
              tooltip: '알림 추가',
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}
