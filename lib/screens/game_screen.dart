import 'dart:async'; // ✅ unawaited
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

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

  bool _loggedStart = false;

  @override
  void initState() {
    super.initState();
    AppAnalytics.screen('game_screen');
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
    _loggedStart = false;

    // ✅ Analytics (fire-and-forget)
    unawaited(AppAnalytics.log('game_restart', params: {'source': 'game_screen'}));

    setState(() {});
  }

  void onNumberTap(int number) async {
    if (number != clicked.length + 1) return;

    // 첫 탭에만 스톱워치 시작 + 시작 이벤트
    if (clicked.isEmpty) {
      stopwatch.start();

      if (!_loggedStart) {
        _loggedStart = true;
        unawaited(AppAnalytics.log('game_start', params: {
          'size': 30,
          'source': 'game_screen',
        }));
      }
    }

    clicked.add(number);
    lastTapped = number;

    // ✅ 탭 즉시 UI 반영
    setState(() {});

    if (number == 30) {
      stopwatch.stop();
      final elapsed = stopwatch.elapsed.inMilliseconds / 1000.0;

      final prevBest = bestRecord;
      bool isNewBest = false;

      if (elapsed < bestRecord) {
        bestRecord = elapsed;
        isNewBest = true;
        await _saveBestRecord(elapsed);
      }

      // ✅ 먼저 다이얼로그 띄우기 (Analytics 지연/오류로 “안 눌림” 체감 방지)
      _showGameClearDialog(elapsed);

      // ✅ Analytics는 뒤에서 안전하게 (예외/지연 무시)
      unawaited(() async {
        try {
          await AppAnalytics.log('game_clear', params: {
            'elapsed_sec': double.parse(elapsed.toStringAsFixed(2)),
            'best_sec': prevBest == double.infinity
                ? -1
                : double.parse(prevBest.toStringAsFixed(2)),
            'is_new_best': isNewBest,
            'source': 'game_screen',
          });
        } catch (_) {}
      }());
    }
  }

  void _showGameClearDialog(double elapsed) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎉 축하합니다!'),
        content: Text(
          '모든 숫자를 완료했습니다!\n\n⏱ 기록: ${elapsed.toStringAsFixed(2)}초',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              resetGame();
            },
            child: const Text('다시 도전하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = stopwatch.elapsed.inMilliseconds / 1000.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(
        backgroundColor: Colors.teal,
        elevation: 3,
        title: const Text(
          '1부터 30까지 빠르게!',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // 상단 기록 카드
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          clicked.length == 30
                              ? '🎯 완료! 기록: ${elapsed.toStringAsFixed(2)}초'
                              : '⏱ 진행 중...',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          bestRecord != double.infinity
                              ? '🏆 최고 기록: ${bestRecord.toStringAsFixed(2)}초'
                              : '아직 최고 기록이 없습니다.',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.teal,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ✅ Grid: 스크롤 끔 + bottom padding으로 제스처 영역 회피
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 24), // ✅ 하단 제스처 영역 회피
                      physics: const NeverScrollableScrollPhysics(), // ✅ 탭 씹힘 방지
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: numbers.length,
                      itemBuilder: (context, index) {
                        final n = numbers[index];
                        final clickedAlready = clicked.contains(n);
                        final isLastTapped = lastTapped == n;

                        final bgColor = clickedAlready
                            ? Colors.grey[300]
                            : isLastTapped
                            ? Colors.orangeAccent
                            : Colors.teal;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: clickedAlready ? null : () => onNumberTap(n),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  if (!clickedAlready)
                                    const BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 6,
                                      offset: Offset(1, 2),
                                    ),
                                ],
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$n',
                                    style: TextStyle(
                                      fontSize: constraints.maxWidth * 0.05,
                                      fontWeight: FontWeight.w700,
                                      color: clickedAlready ? Colors.black54 : Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 하단 버튼
                  SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: resetGame,
                        icon: const Icon(Icons.refresh, size: 22),
                        label: const Text(
                          '다시 시작',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}