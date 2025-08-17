import 'package:flutter/material.dart';

class HealthScreen extends StatelessWidget {
  final Duration quitDuration;
  const HealthScreen({super.key, required this.quitDuration});

  @override
  Widget build(BuildContext context) {
    final healthStages = [
      {'label': '20분', 'minutes': 20, 'description': '혈압과 맥박이 정상으로 회복됩니다.'},
      {'label': '8시간', 'minutes': 480, 'description': '혈액 내 산소 수치가 정상으로 돌아옵니다.'},
      {'label': '24시간', 'minutes': 1440, 'description': '심장마비 위험이 감소합니다.'},
      {'label': '48시간', 'minutes': 2880, 'description': '후각과 미각이 향상됩니다.'},
      {'label': '72시간', 'minutes': 4320, 'description': '기관지가 이완되고 폐기능이 향상됩니다.'},
      {'label': '2주~3개월', 'minutes': 40320, 'description': '혈액순환과 폐기능이 눈에 띄게 개선됩니다.'},
      {'label': '1~9개월', 'minutes': 403200, 'description': '기침, 피로감, 호흡곤란이 줄어듭니다.'},
      {'label': '1년', 'minutes': 525600, 'description': '관상동맥 심장질환 위험이 절반으로 감소합니다.'},
    ];

    final totalMinutes = quitDuration.inMinutes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('건강 개선 현황'),
        backgroundColor: Colors.deepOrange,
      ),
      body: ListView.builder(
        itemCount: healthStages.length,
        itemBuilder: (context, index) {
          final stage = healthStages[index];
          final completed = totalMinutes >= (stage['minutes'] as num).toInt();

          return ListTile(
            leading: Icon(
              completed ? Icons.check_circle : Icons.radio_button_unchecked,
              color: completed ? Colors.green : Colors.grey,
            ),
            title: Text(stage['label'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            subtitle: Text(stage['description'] as String),
          );
        },
      ),
    );
  }
}