import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class HealthStage {
  final String label;
  final int minutes;
  final String description;

  const HealthStage({
    required this.label,
    required this.minutes,
    required this.description,
  });
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  DateTime? _startTime;
  Duration quitDuration = Duration.zero;
  Timer? _timer;

  final List<HealthStage> healthStages = const [
    HealthStage(
      label: '20분',
      minutes: 20,
      description: '혈압과 맥박이 정상으로 회복됩니다.',
    ),
    HealthStage(
      label: '8시간',
      minutes: 8 * 60,
      description: '혈액 내 산소 수치가 정상으로 돌아옵니다.',
    ),
    HealthStage(
      label: '24시간',
      minutes: 24 * 60,
      description: '심장마비 위험이 감소합니다.',
    ),
    HealthStage(
      label: '48시간',
      minutes: 48 * 60,
      description: '후각과 미각이 향상됩니다.',
    ),
    HealthStage(
      label: '72시간',
      minutes: 72 * 60,
      description: '기관지가 이완되고 폐기능이 향상됩니다.',
    ),
    HealthStage(
      label: '2주~3개월',
      minutes: 14 * 24 * 60,
      description: '혈액순환과 폐기능이 눈에 띄게 개선됩니다.',
    ),
    HealthStage(
      label: '1~9개월',
      minutes: 30 * 24 * 60,
      description: '기침, 피로감, 호흡곤란이 줄어듭니다.',
    ),
    HealthStage(
      label: '1년',
      minutes: 365 * 24 * 60,
      description: '관상동맥 심장질환 위험이 절반으로 감소합니다.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadStartTime();
  }

  Future<void> _loadStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt('startTime');

    if (millis != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(millis);
      _updateDuration();

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _updateDuration();
      });
    }
  }

  void _updateDuration() {
    if (_startTime == null) return;
    final now = DateTime.now();
    setState(() {
      quitDuration = now.difference(_startTime!);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);

    if (days > 0) {
      return '$days일 $hours시간 $minutes분';
    }
    if (hours > 0) {
      return '$hours시간 $minutes분';
    }
    return '${minutes}분';
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = quitDuration.inMinutes;
    const maxMinutes = 525600; // 1년
    final progress = (totalMinutes / maxMinutes).clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('건강 개선 현황'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Column(
        children: [
          // Progress
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '금연 진행률: $percent%',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '경과 시간: ${_formatDuration(quitDuration)}',
                  style: const TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 14,
                  backgroundColor: Colors.grey.shade300,
                  valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: healthStages.length,
              itemBuilder: (context, index) {
                final stage = healthStages[index];
                final completed = totalMinutes >= stage.minutes;

                return ListTile(
                  leading: Icon(
                    completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: completed ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    stage.label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(stage.description),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}