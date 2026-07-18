import 'dart:convert';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/bff_auth_service.dart';
import '../theme/app_theme.dart';
import '../notifications/daily_reminder_worker.dart';
import '../supabase/supabase_config.dart';
import '../api/reasons_api_service.dart';
import '../widget/widget_helper.dart';

class ReasonWhyScreen extends StatefulWidget {
  const ReasonWhyScreen({super.key});

  @override
  State<ReasonWhyScreen> createState() => _ReasonWhyScreenState();
}

class _ReasonItem {
  final String id;
  String text;
  bool pinned;
  final int createdAt;
  int displayNumber; // 별표로 상단 이동해도 번호 유지

  _ReasonItem({
    required this.id,
    required this.text,
    required this.pinned,
    required this.createdAt,
    required this.displayNumber,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'pinned': pinned,
        'createdAt': createdAt,
        'displayNumber': displayNumber,
      };

  static _ReasonItem fromJson(Map<String, dynamic> json) {
    return _ReasonItem(
      id: (json['id'] as String?) ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      text: (json['text'] as String?) ?? '',
      pinned: (json['pinned'] as bool?) ?? false,
      createdAt: (json['createdAt'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
      displayNumber: (json['displayNumber'] as int?) ?? 0,
    );
  }
}

class _ReasonWhyScreenState extends State<ReasonWhyScreen> {
  static const String _prefsKey = 'quitReasons_v1';
  static const String _selectedReasonIdKey = 'selectedReasonId';

  /// 빈 화면·여백을 채우는 예시 (탭하면 내 이유로 추가)
  static const List<({String emoji, String text})> _exampleReasons = [
    (emoji: '❤️', text: '가족과 더 오래 건강하게 함께하기 위해'),
    (emoji: '🫁', text: '숨이 편해지고, 운동이 즐거워지도록'),
    (emoji: '💰', text: '담배값으로 나다운 취미에 투자하려고'),
    (emoji: '✨', text: '냄새가 아닌, 나답게 기억되고 싶어서'),
    (emoji: '🌱', text: '작은 약속을 지키는 사람이 되고 싶어서'),
    (emoji: '👶', text: '아이·손주에게 당당한 모습을 보여주려고'),
  ];

  final List<_ReasonItem> _reasons = [];
  final ReasonsApiService _reasonsApi = const ReasonsApiService();
  String? _selectedReasonId;
  bool _reasonNotificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedReasonId = prefs.getString(_selectedReasonIdKey);
    _reasonNotificationEnabled =
        prefs.getBool(kReasonNotificationEnabledKey) ?? false;

    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      setState(() {});
      unawaited(_syncReasonsFromApiIfAvailable());
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        var loaded = decoded
            .whereType<Map>()
            .map((m) => _ReasonItem.fromJson(Map<String, dynamic>.from(m)))
            .where((r) => r.text.trim().isNotEmpty)
            .toList();
        final byCreated = List<_ReasonItem>.from(loaded)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        for (var i = 0; i < byCreated.length; i++) {
          if (byCreated[i].displayNumber <= 0) {
            byCreated[i].displayNumber = i + 1;
          }
        }
        final pinnedCount = loaded.where((r) => r.pinned).length;
        if (pinnedCount > 1) {
          var foundFirst = false;
          for (final r in loaded) {
            if (r.pinned) {
              if (foundFirst) {
                r.pinned = false;
              } else {
                foundFirst = true;
              }
            }
          }
        }
        setState(() {
          _reasons
            ..clear()
            ..addAll(loaded);
          _sortReasons();
        });
        await _saveReasons(syncApi: false);
        unawaited(_syncReasonsFromApiIfAvailable());
      } else {
        setState(() {});
        unawaited(_syncReasonsFromApiIfAvailable());
      }
    } catch (_) {
      setState(() {});
      unawaited(_syncReasonsFromApiIfAvailable());
    }
  }

  Future<void> _selectReasonForNotification(int index) async {
    final item = _reasons[index];
    final isCurrentlySelected = _selectedReasonId == item.id;
    if (isCurrentlySelected) {
      await _disableReasonNotification();
      return;
    }
    if (mounted) {
      setState(() {
        _selectedReasonId = item.id;
        _reasonNotificationEnabled = true;
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedReasonIdKey, item.id);
    await prefs.setString(kSelectedReasonTextKey, item.text);
    await prefs.setBool(kReasonNotificationEnabledKey, true);
    unawaited(scheduleReasonReminder());
    unawaited(_pushReasonsToApiIfAvailable());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('매일 12:00에 선택한 이유로 알림이 옵니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _disableReasonNotification() async {
    if (mounted) {
      setState(() {
        _reasonNotificationEnabled = false;
        _selectedReasonId = null;
      });
    }
    unawaited(disableReasonReminder());
    unawaited(_pushReasonsToApiIfAvailable());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('금연 이유 알림이 해지되었습니다.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static const String _pinnedReasonTextKey = 'pinnedReasonText';

  Future<void> _saveReasons({bool syncApi = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_reasons.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
    final pinnedList = _reasons.where((r) => r.pinned).toList();
    final pinned = pinnedList.isEmpty ? null : pinnedList.first;
    if (pinned != null) {
      await prefs.setString(_pinnedReasonTextKey, pinned.text);
    } else {
      await prefs.remove(_pinnedReasonTextKey);
    }
    await syncWidgetData();
    if (syncApi) {
      unawaited(_pushReasonsToApiIfAvailable());
    }
  }

  List<Map<String, dynamic>> _serializeReasonsForApi() {
    return _reasons.map((r) => r.toJson()).toList();
  }

  Future<void> _pushReasonsToApiIfAvailable() async {
    if (!SupabaseConfig.isConfigured) return;
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token == null || token.isEmpty) return;
    final pinned =
        _reasons.where((r) => r.pinned).map((r) => r.text.trim()).firstWhere(
              (t) => t.isNotEmpty,
              orElse: () => '',
            );
    final selectedText = _reasons
        .where((r) => r.id == _selectedReasonId)
        .map((r) => r.text)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    try {
      await _reasonsApi.syncReasonState(
        accessToken: token,
        reasons: _serializeReasonsForApi(),
        pinnedReasonText: pinned,
        selectedReasonId: _selectedReasonId,
        selectedReasonText: selectedText,
      );
    } catch (_) {
      // 로컬 우선 정책: 실패 시 무시
    }
  }

  Future<void> _syncReasonsFromApiIfAvailable() async {
    if (!SupabaseConfig.isConfigured) return;
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token == null || token.isEmpty) return;
    try {
      final remote = await _reasonsApi.fetchReasonState(accessToken: token);
      if (remote == null) return;
      if (remote.reasons.isEmpty && remote.pinnedReasonText.isEmpty) return;

      final loaded = remote.reasons
          .map((m) => _ReasonItem.fromJson(m))
          .where((r) => r.text.trim().isNotEmpty)
          .toList();
      if (loaded.isEmpty && remote.pinnedReasonText.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        loaded.add(_ReasonItem(
          id: now.toString(),
          text: remote.pinnedReasonText,
          pinned: true,
          createdAt: now,
          displayNumber: 1,
        ));
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(loaded.map((e) => e.toJson()).toList()),
      );
      if (remote.pinnedReasonText.isNotEmpty) {
        await prefs.setString(_pinnedReasonTextKey, remote.pinnedReasonText);
      }
      if (remote.selectedReasonId != null) {
        await prefs.setString(_selectedReasonIdKey, remote.selectedReasonId!);
      }
      if (remote.selectedReasonText != null) {
        await prefs.setString(
            kSelectedReasonTextKey, remote.selectedReasonText!);
      }

      await syncWidgetData();

      if (!mounted) return;
      setState(() {
        _reasons
          ..clear()
          ..addAll(loaded);
        _selectedReasonId = remote.selectedReasonId ?? _selectedReasonId;
        _sortReasons();
      });
    } catch (_) {
      // 로컬 우선 정책: 실패 시 무시
    }
  }

  void _sortReasons() {
    _reasons.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _addReason({String? preset}) async {
    final reason = preset ??
        await _showInputDialog(context, title: '금연 이유 추가');
    if (reason == null) return;

    final trimmed = reason.trim();
    if (trimmed.isEmpty) return;

    // 이미 같은 문구가 있으면 추가하지 않음
    if (_reasons.any((r) => r.text.trim() == trimmed)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 같은 이유가 있어요.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final nextNum = _reasons.isEmpty
        ? 1
        : (_reasons.map((r) => r.displayNumber).reduce((a, b) => a > b ? a : b) +
            1);
    final item = _ReasonItem(
      id: now.toString(),
      text: trimmed,
      pinned: false,
      createdAt: now,
      displayNumber: nextNum,
    );

    setState(() {
      _reasons.add(item);
      _sortReasons();
    });
    await _saveReasons();
  }

  Future<void> _editReason(int index) async {
    final edited = await _showInputDialog(
      context,
      title: '금연 이유 수정',
      initialValue: _reasons[index].text,
    );
    if (edited == null) return;

    final trimmed = edited.trim();
    if (trimmed.isEmpty) return;

    final item = _reasons[index];
    setState(() {
      item.text = trimmed;
      _sortReasons();
    });
    await _saveReasons();
    if (_selectedReasonId == item.id) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSelectedReasonTextKey, trimmed);
    }
  }

  Future<void> _togglePin(int index) async {
    setState(() {
      final currentlyPinned = _reasons[index].pinned;
      for (var i = 0; i < _reasons.length; i++) {
        _reasons[i].pinned = false;
      }
      if (!currentlyPinned) {
        _reasons[index].pinned = true;
      }
      _sortReasons();
    });
    await _saveReasons();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_reasons.any((r) => r.pinned)
            ? '중요 이유로 고정되었습니다. (흡연 욕구 시 표시됩니다.)'
            : '고정이 해제되었습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteReason(int index) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final removed = _reasons[index];
    final wasSelected = _selectedReasonId == removed.id;

    setState(() {
      _reasons.removeAt(index);
      if (wasSelected) {
        _selectedReasonId = null;
        _reasonNotificationEnabled = false;
      }
    });
    await _saveReasons();
    if (wasSelected) await disableReasonReminder();

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        // 확인을 누를 때까지 유지 (자동 소멸으로 남아 보이는 문제 방지)
        duration: const Duration(days: 1),
        dismissDirection: DismissDirection.horizontal,
        content: Row(
          children: [
            const Expanded(
              child: Text('금연 이유를 삭제했습니다.'),
            ),
            TextButton(
              onPressed: () async {
                final insertIndex = index.clamp(0, _reasons.length);
                messenger.hideCurrentSnackBar();
                if (!mounted) return;
                setState(() {
                  _reasons.insert(insertIndex, removed);
                  _sortReasons();
                });
                await _saveReasons();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('되돌리기'),
            ),
            TextButton(
              onPressed: () => messenger.hideCurrentSnackBar(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('이 금연 이유를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteReason(index);
    }
  }

  Future<String?> _showInputDialog(
    BuildContext context, {
    String title = '',
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '금연 이유를 입력하세요'),
          autofocus: true,
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  List<({String emoji, String text})> get _unusedExamples {
    final mine = _reasons.map((r) => r.text.trim()).toSet();
    return _exampleReasons
        .where((e) => !mine.contains(e.text.trim()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final examples = _unusedExamples;
    final showExamples = examples.isNotEmpty && _reasons.length < 5;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('내가 금연하는 이유'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            Navigator.of(context).maybePop();
          },
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroHeader(
                    notificationOn: _reasonNotificationEnabled,
                    onDisableNotification: _reasonNotificationEnabled
                        ? _disableReasonNotification
                        : null,
                  ),
                  const SizedBox(height: 20),
                  if (_reasons.isNotEmpty)
                    Text(
                      '나의 이유',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  if (_reasons.isNotEmpty) const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          if (_reasons.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: _EmptyHint(),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _reasons[index];
                    final isSelected = _selectedReasonId == item.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReasonCard(
                        item: item,
                        isSelected: isSelected,
                        onNotify: () => _selectReasonForNotification(index),
                        onPin: () => _togglePin(index),
                        onEdit: () => _editReason(index),
                        onDelete: () => _confirmDelete(index),
                      ),
                    );
                  },
                  childCount: _reasons.length,
                ),
              ),
            ),
          if (showExamples)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _ExampleSection(
                  examples: examples,
                  onTap: (text) => _addReason(preset: text),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addReason(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('이유 추가'),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.notificationOn,
    this.onDisableNotification,
  });

  final bool notificationOn;
  final VoidCallback? onDisableNotification;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.12),
            AppTheme.primarySurface,
            const Color(0xFFF0F7F5),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '왜 끊고 싶은지, 한 문장으로',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '종 아이콘을 누르면 매일 12:00에 그 이유가 알림으로 와요. '
            '별은 흡연 욕구가 올 때 가장 먼저 보여 줄 이유를 고정해요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.45,
                ),
          ),
          if (notificationOn && onDisableNotification != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDisableNotification,
                icon: const Icon(Icons.notifications_off_outlined, size: 18),
                label: const Text('알림 끄기'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 48,
            color: AppTheme.primary.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            '아직 적은 이유가 없어요',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '아래에서 예시를 고르거나, + 로 직접 적어 보세요.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({
    required this.item,
    required this.isSelected,
    required this.onNotify,
    required this.onPin,
    required this.onEdit,
    required this.onDelete,
  });

  final _ReasonItem item;
  final bool isSelected;
  final VoidCallback onNotify;
  final VoidCallback onPin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.pinned
              ? AppTheme.accent.withValues(alpha: 0.35)
              : isSelected
                  ? AppTheme.primary.withValues(alpha: 0.28)
                  : AppTheme.border,
        ),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item.displayNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.text,
                        style: AppTheme.bodyLarge.copyWith(height: 1.4),
                      ),
                      if (item.pinned || isSelected) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (item.pinned)
                              _StatusChip(
                                icon: Icons.push_pin_rounded,
                                label: '중요 고정',
                                color: AppTheme.accent,
                              ),
                            if (isSelected)
                              _StatusChip(
                                icon: Icons.notifications_active_rounded,
                                label: '매일 12:00',
                                color: AppTheme.primary,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                _ActionIcon(
                  icon: isSelected
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                  tooltip: isSelected ? '알림 해지' : '매일 알림',
                  onTap: onNotify,
                ),
                _ActionIcon(
                  icon: item.pinned
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: item.pinned ? AppTheme.accent : AppTheme.textMuted,
                  tooltip: item.pinned ? '고정 해제' : '중요 고정',
                  onTap: onPin,
                ),
                _ActionIcon(
                  icon: Icons.edit_outlined,
                  color: AppTheme.textSecondary,
                  tooltip: '수정',
                  onTap: onEdit,
                ),
                _ActionIcon(
                  icon: Icons.delete_outline_rounded,
                  color: AppTheme.error.withValues(alpha: 0.85),
                  tooltip: '삭제',
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: 22, color: color),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

class _ExampleSection extends StatelessWidget {
  const _ExampleSection({
    required this.examples,
    required this.onTap,
  });

  final List<({String emoji, String text})> examples;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '이런 이유도 있어요',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 8),
            Text(
              '탭하면 추가',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...examples.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(e.text),
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.border,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(e.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.text,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                height: 1.35,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 20,
                        color: AppTheme.primary.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
