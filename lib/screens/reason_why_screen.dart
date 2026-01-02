import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReasonWhyScreen extends StatefulWidget {
  const ReasonWhyScreen({super.key});

  @override
  State<ReasonWhyScreen> createState() => _ReasonWhyScreenState();
}

class _ReasonItem {
  final String id; // 고유값(undo/수정/핀 유지용)
  String text;
  bool pinned;
  final int createdAt; // 정렬 안정성(최근 추가 우선)

  _ReasonItem({
    required this.id,
    required this.text,
    required this.pinned,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'pinned': pinned,
    'createdAt': createdAt,
  };

  static _ReasonItem fromJson(Map<String, dynamic> json) {
    return _ReasonItem(
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: (json['text'] as String?) ?? '',
      pinned: (json['pinned'] as bool?) ?? false,
      createdAt: (json['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class _ReasonWhyScreenState extends State<ReasonWhyScreen> {
  static const String _prefsKey = 'quitReasons_v1';

  final List<_ReasonItem> _reasons = [];

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  Future<void> _loadReasons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final loaded = decoded
            .whereType<Map>()
            .map((m) => _ReasonItem.fromJson(Map<String, dynamic>.from(m)))
            .where((r) => r.text.trim().isNotEmpty)
            .toList();

        setState(() {
          _reasons
            ..clear()
            ..addAll(loaded);
          _sortReasons();
        });
      }
    } catch (_) {
      // 저장 포맷이 깨졌을 때 앱이 죽지 않도록 무시
    }
  }

  Future<void> _saveReasons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_reasons.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
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
    final item = _ReasonItem(
      id: now.toString(),
      text: trimmed,
      pinned: false,
      createdAt: now,
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

    setState(() {
      _reasons[index].text = trimmed;
      // 수정은 순서를 바꾸지 않되, 정렬 규칙 유지(핀/비핀 구간에서 안정)
      _sortReasons();
    });
    await _saveReasons();
  }

  Future<void> _togglePin(int index) async {
    setState(() {
      _reasons[index].pinned = !_reasons[index].pinned;
      _sortReasons();
    });
    await _saveReasons();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_reasons.any((r) => r.pinned) ? '중요 이유 고정 상태가 업데이트되었습니다.' : '고정이 해제되었습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteReason(int index) async {
    // 삭제 전 기존 스낵바 닫기 (undo 충돌 방지)
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final removed = _reasons[index];

    // ✅ 즉시 삭제 + 저장
    setState(() {
      _reasons.removeAt(index);
    });
    await _saveReasons();

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
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
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
      appBar: AppBar(
        title: const Text('내가 금연하는 이유'),
        backgroundColor: Colors.redAccent,
      ),
      body: _reasons.isEmpty
          ? const Center(
        child: Text(
          '아직 작성한 금연 이유가 없습니다.\n오른쪽 아래 + 버튼을 눌러 추가해보세요!',
          textAlign: TextAlign.center,
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reasons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _reasons[index];
          final number = _reasons.length - index;

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: item.pinned ? Colors.amber.shade700 : Colors.grey,
              ),
              title: Text(
                '$number. ${item.text}',
                style: const TextStyle(fontSize: 16),
              ),
              subtitle: item.pinned
                  ? const Text('중요 이유로 고정됨', style: TextStyle(color: Colors.black54))
                  : null,
              trailing: Wrap(
                spacing: 6,
                children: [
                  IconButton(
                    icon: Icon(
                      item.pinned ? Icons.star : Icons.star_border,
                      color: item.pinned ? Colors.amber.shade700 : Colors.grey,
                    ),
                    onPressed: () => _togglePin(index),
                    tooltip: item.pinned ? '고정 해제' : '중요 이유 고정',
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _editReason(index),
                    tooltip: '수정',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDelete(index),
                    tooltip: '삭제',
                  ),
                ],
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReason,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
        tooltip: '금연 이유 추가',
      ),
    );
  }
}