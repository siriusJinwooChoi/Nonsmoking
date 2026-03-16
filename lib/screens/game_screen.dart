import 'dart:async'; // ✅ unawaited
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../ad_manager.dart';

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

  static const int _maxNumber = 30;

  void resetGame() {
    final rand = Random();
    numbers = List.generate(_maxNumber, (index) => index + 1);
    numbers.shuffle(rand);

    clicked.clear();
    lastTapped = null;
    stopwatch.reset();
    _loggedStart = false;

    unawaited(AppAnalytics.log('game_restart', params: {'source': 'game_screen'}));
    setState(() {});
  }

  void onNumberTap(int number) async {
    if (number != clicked.length + 1) return;

    // 1을 누르는 순간 스톱워치 시작
    if (clicked.isEmpty) {
      stopwatch.start();
      if (!_loggedStart) {
        _loggedStart = true;
        unawaited(AppAnalytics.log('game_start', params: {
          'size': _maxNumber,
          'source': 'game_screen',
        }));
      }
    }

    clicked.add(number);
    lastTapped = number;
    setState(() {});

    // 30을 누르면 시간 정지 후 기록 표시
    if (number == _maxNumber) {
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
      _showGameClearDialog(elapsed, isNewBest);

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

  void _showGameClearDialog(double elapsed, [bool isNewBest = false]) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('축하합니다!'),
        content: Text(
          '1부터 30까지 완료했습니다!\n\n'
          '기록: ${elapsed.toStringAsFixed(2)}초'
          '${isNewBest ? '\n\n🎉 새 최고 기록!' : ''}',
          textAlign: TextAlign.center,
          style: AppTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              AdManager.showAd(onAdClosed: () {
                if (context.mounted) resetGame();
              });
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
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('1부터 30까지 빠르게!'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: [
                  // 상단 기록 카드 (컴팩트)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.cardShadowSubtle,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          clicked.length == _maxNumber
                              ? '완료! ${elapsed.toStringAsFixed(2)}초'
                              : '진행 중 (${clicked.length}/$_maxNumber)',
                          style: AppTheme.titleMedium.copyWith(fontSize: 15),
                        ),
                        Text(
                          bestRecord != double.infinity
                              ? '최고: ${bestRecord.toStringAsFixed(2)}초'
                              : '최고 기록 없음',
                          style: AppTheme.bodyMedium.copyWith(color: AppTheme.primary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 1~30 숫자 그리드 (5열 x 6행, 한 화면에 수납)
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 6),
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 1.05,
                      ),
                      itemCount: numbers.length,
                      itemBuilder: (context, index) {
                        final n = numbers[index];
                        final clickedAlready = clicked.contains(n);
                        final isLastTapped = lastTapped == n;

                        final bgColor = clickedAlready
                            ? AppTheme.textMuted.withOpacity(0.4)
                            : isLastTapped
                            ? AppTheme.warning
                            : AppTheme.primary;

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
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: clickedAlready ? AppTheme.textSecondary : Colors.white,
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

                  const SizedBox(height: 6),

                  // 하단 버튼
                  SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: resetGame,
                        icon: const Icon(Icons.refresh_rounded, size: 22),
                        label: const Text('다시 시작'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
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