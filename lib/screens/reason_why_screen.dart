import 'package:flutter/material.dart';

class ReasonWhyScreen extends StatefulWidget {
  const ReasonWhyScreen({super.key});

  @override
  State<ReasonWhyScreen> createState() => _ReasonWhyScreenState();
}

class _ReasonWhyScreenState extends State<ReasonWhyScreen> {
  final List<String> _reasons = [];

  void _addReason() async {
    final reason = await _showInputDialog(context, title: '금연 이유 추가');
    if (reason != null && reason.trim().isNotEmpty) {
      setState(() => _reasons.insert(0, reason.trim()));
    }
  }

  void _editReason(int index) async {
    final edited = await _showInputDialog(
      context,
      title: '금연 이유 수정',
      initialValue: _reasons[index],
    );
    if (edited != null && edited.trim().isNotEmpty) {
      setState(() => _reasons[index] = edited.trim());
    }
  }

  void _deleteReason(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('이 금연 이유를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _reasons.removeAt(index));
              Navigator.pop(context);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<String?> _showInputDialog(BuildContext context,
      {String title = '', String initialValue = ''}) {
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
        child: Text('아직 작성한 금연 이유가 없습니다.\n오른쪽 아래 + 버튼을 눌러 추가해보세요!',
            textAlign: TextAlign.center),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _reasons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final number = _reasons.length - index;
          final reason = _reasons[index];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: Text(
                '$number. $reason',
                style: const TextStyle(fontSize: 16),
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _editReason(index),
                    tooltip: '수정',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteReason(index),
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