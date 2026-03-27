import 'dart:convert';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../notifications/daily_reminder_worker.dart';
import '../supabase/supabase_config.dart';
import '../api/reasons_api_service.dart';

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
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: (json['text'] as String?) ?? '',
      pinned: (json['pinned'] as bool?) ?? false,
      createdAt: (json['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      displayNumber: (json['displayNumber'] as int?) ?? 0,
    );
  }
}

class _ReasonWhyScreenState extends State<ReasonWhyScreen> {
  static const String _prefsKey = 'quitReasons_v1';
  static const String _selectedReasonIdKey = 'selectedReasonId';

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
    _reasonNotificationEnabled = prefs.getBool(kReasonNotificationEnabledKey) ?? false;

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
        // 기존 데이터에 displayNumber 없으면 생성 순서로 1,2,3... 부여
        final byCreated = List<_ReasonItem>.from(loaded)..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        for (var i = 0; i < byCreated.length; i++) {
          if (byCreated[i].displayNumber <= 0) {
            byCreated[i].displayNumber = i + 1;
          }
        }
        // 별표는 하나만: 여러 개 고정된 경우 첫 번째만 남김
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
    // UI는 즉시 반영하고, 예약 작업은 뒤에서 수행해 체감 지연을 줄입니다.
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
      const SnackBar(content: Text('매일 12:00에 선택한 이유로 알림이 옵니다.'), duration: Duration(seconds: 2)),
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
      const SnackBar(content: Text('금연 이유 알림이 해지되었습니다.'), duration: Duration(seconds: 2)),
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
    if (syncApi) {
      unawaited(_pushReasonsToApiIfAvailable());
    }
  }

  List<Map<String, dynamic>> _serializeReasonsForApi() {
    return _reasons.map((r) => r.toJson()).toList();
  }

  Future<void> _pushReasonsToApiIfAvailable() async {
    if (!SupabaseConfig.isConfigured) return;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return;
    final pinned = _reasons.where((r) => r.pinned).map((r) => r.text.trim()).firstWhere(
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
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
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
        await prefs.setString(kSelectedReasonTextKey, remote.selectedReasonText!);
      }

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
    // ✅ 핀된 이유 먼저, 그 다음은 createdAt 최신순(최근 추가가 위로)
    _reasons.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _addReason() async {
    final reason = await _showInputDialog(context, title: '금연 이유 추가');
    if (reason == null) return;

    final trimmed = reason.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final nextNum = _reasons.isEmpty ? 1 : (_reasons.map((r) => r.displayNumber).reduce((a, b) => a > b ? a : b) + 1);
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

  /// 별표는 하나만 선택: 다른 건 모두 해제 후 이 항목만 고정(또는 해제)
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
        content: Text(_reasons.any((r) => r.pinned) ? '중요 이유로 고정되었습니다. (흡연 욕구 시 표시됩니다.)' : '고정이 해제되었습니다.'),
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

    // ✅ 되돌리기(Undo)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('금연 이유를 삭제했습니다.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () async {
            // 원래 인덱스가 범위를 벗어나면 뒤에 붙임
            final insertIndex = index.clamp(0, _reasons.length);
            setState(() {
              _reasons.insert(insertIndex, removed);
              _sortReasons();
            });
            await _saveReasons();
          },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('내가 금연하는 이유'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '이유 중에 하나를 선택하여 종 버튼을 누르시면 매일 점심시간(12:00)마다 금연 알림이 제공됩니다.',
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_reasonNotificationEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextButton.icon(
                onPressed: _disableReasonNotification,
                icon: const Icon(Icons.notifications_off_rounded, size: 20),
                label: const Text('금연 이유 알림 해지'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
            ),
          Expanded(
            child: _reasons.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_note_rounded, size: 64, color: AppTheme.textMuted),
                    const SizedBox(height: 16),
                    Text(
                      '아직 작성한 금연 이유가 없습니다.',
                      textAlign: TextAlign.center,
                      style: AppTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '오른쪽 아래 + 버튼을 눌러 추가해보세요.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: _reasons.length,
              itemBuilder: (context, index) {
                final item = _reasons[index];
                final isSelected = _selectedReasonId == item.id;
                return Container(
                  key: ValueKey(item.id),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.cardShadowSubtle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                          color: item.pinned ? AppTheme.warning : AppTheme.textMuted,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${item.displayNumber}. ${item.text}',
                                style: AppTheme.bodyLarge,
                                maxLines: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.pinned || isSelected) ...[
                                const SizedBox(height: 4),
                                if (item.pinned)
                                  Text('중요 이유로 고정됨', style: AppTheme.labelMedium),
                                if (isSelected)
                                  Text('매일 12:00 알림 사용 중', style: AppTheme.labelMedium.copyWith(color: AppTheme.primary)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 2x2 아이콘 그리드 (종, 별 / 연필, 휴지통)
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.3)),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isSelected ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                                      color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                                      size: 22,
                                    ),
                                    onPressed: () => _selectReasonForNotification(index),
                                    tooltip: isSelected ? '알림 해지' : '이 이유로 매일 알림 받기',
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      item.pinned ? Icons.star_rounded : Icons.star_border_rounded,
                                      color: item.pinned ? AppTheme.warning : AppTheme.textMuted,
                                      size: 22,
                                    ),
                                    onPressed: () => _togglePin(index),
                                    tooltip: item.pinned ? '고정 해제' : '중요 이유 고정',
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: AppTheme.primary, size: 22),
                                    onPressed: () => _editReason(index),
                                    tooltip: '수정',
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_rounded, color: AppTheme.error, size: 22),
                                    onPressed: () => _confirmDelete(index),
                                    tooltip: '삭제',
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReason,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}