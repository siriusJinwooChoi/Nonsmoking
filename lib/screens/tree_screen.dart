import 'package:flutter/material.dart';

class TreeScreen extends StatefulWidget {
  const TreeScreen({super.key});

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> {
  int water = 0;
  int growthStage = 1;
  final Map<int, int> stageGoal = {
    1: 600,
    2: 3000,
    3: 13200,
    4: 87600,
  };

  void giveWater() {
    setState(() {
      water += 10;
      if (growthStage < 5 && water >= stageGoal[growthStage]!) {
        growthStage++;
        water = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final percent = growthStage < 5
        ? ((water / stageGoal[growthStage]!) * 100).clamp(0, 100).toStringAsFixed(0)
        : '100';

    return Scaffold(
      appBar: AppBar(
        title: const Text('나무 키우기'),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '나무는 최대 5단계까지 성장합니다! 꼭 성공하세요.',
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Image.asset('assets/tree_stage_$growthStage.png', height: 180),
            const SizedBox(height: 20),
            Text('현재 단계: $growthStage단계', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            Text('성장률: $percent%', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: giveWater,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue),
              child: const Text('💧 물 주기 (10g)', style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      ),
    );
  }
}