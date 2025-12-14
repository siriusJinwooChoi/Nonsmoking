import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late List<int> numbers;
  List<int> clicked = [];
  Stopwatch stopwatch = Stopwatch();
  double bestRecord = double.infinity;
  int? lastTapped;

  @override
  void initState() {
    super.initState();
    _loadBestRecord();
    resetGame();
  }

  Future<void> _loadBestRecord() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      bestRecord = prefs.getDouble('bestRecord') ?? double.infinity;
    });
  }

  Future<void> _saveBestRecord(double newRecord) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bestRecord', newRecord);
  }

  void resetGame() {
    final rand = Random();
    numbers = List.generate(30, (index) => index + 1);
    numbers.shuffle(rand);
    clicked.clear();
    lastTapped = null;
    stopwatch.reset();
    setState(() {});
  }

  void onNumberTap(int number) {
    if (number == clicked.length + 1) {
      if (clicked.isEmpty) stopwatch.start();
      clicked.add(number);
      lastTapped = number;
      if (number == 30) {
        stopwatch.stop();
        final elapsed = stopwatch.elapsed.inMilliseconds / 1000.0;
        if (elapsed < bestRecord) {
          bestRecord = elapsed;
          _saveBestRecord(elapsed);
        }
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = stopwatch.elapsed.inMilliseconds / 1000.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('1부터 30까지 빠르게 누르세요!'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              '현재 기록: ${clicked.length == 30 ? '${elapsed.toStringAsFixed(2)}초' : '진행 중...'}',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              bestRecord != double.infinity
                  ? '최고 기록: ${bestRecord.toStringAsFixed(2)}초'
                  : '최고 기록 없음',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1, // ✅ 칸 비율 조정 (작게 보이게)
                ),
                itemCount: numbers.length,
                itemBuilder: (context, index) {
                  final n = numbers[index];
                  final clickedAlready = clicked.contains(n);
                  final isLastTapped = lastTapped == n;

                  return GestureDetector(
                    onTap: clickedAlready ? null : () => onNumberTap(n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: clickedAlready
                            ? Colors.grey[300]
                            : isLastTapped
                            ? Colors.orangeAccent
                            : Colors.teal,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: isLastTapped
                            ? [
                          BoxShadow(
                            color:
                            Colors.orangeAccent.withOpacity(0.6),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          '$n',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: resetGame,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('리셋'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}