import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../supabase/supabase_sync_service.dart';
import '../theme/app_theme.dart';
import 'attendance_screen.dart';
import '../widgets/banner_ad_bar.dart';

/// 완벽 타이밍: 움직이는 표시가 중앙에 올 때 탭하는 타이밍 게임
class TimingTapGameScreen extends StatefulWidget {
  const TimingTapGameScreen({super.key});

  @override
  State<TimingTapGameScreen> createState() => _TimingTapGameScreenState();
}

class _TimingTapGameScreenState extends State<TimingTapGameScreen> {
  static const String _bestScoreKey = 'timing_tap_best_score';
  static const int _maxLevel = 50;
  static const double _targetCenter = 0.5;
  static const double _targetWidth = 0.18; // 중앙 영역 폭

  Timer? _timer;
  double _position = 0; // 0.0 ~ 1.0
  bool _running = false;
  int _level = 1;
  int _score = 0;
  int _bestScore = 0;
  String _lastResult = '중앙에 가까울수록 높은 점수!';
  bool _isFailDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _loadBestScore();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _bestScore = prefs.getInt(_bestScoreKey) ?? 0;
    });
  }

  double get _speedPerSecond {
    // 레벨이 올라갈수록 더 빨라짐 (초당 진행 비율)
    final base = 0.7;
    final extra = (_level - 1) * 0.03;
    return base + extra.clamp(0.0, 1.3);
  }

  void _startRound() {
    _timer?.cancel();
    setState(() {
      _position = 0;
      _running = true;
      _lastResult = '타이밍을 맞춰 보세요!';
    });
    const tick = Duration(milliseconds: 16);
    _timer = Timer.periodic(tick, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_running) {
        t.cancel();
        return;
      }
      final dt = tick.inMilliseconds / 1000.0;
      setState(() {
        _position += _speedPerSecond * dt;
      });
      if (_position >= 1.0) {
        // 시간 초과
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    setState(() {
      _lastResult = '시간 초과! 실패했습니다.';
      _position = 1.0;
    });
    unawaited(_showFailDialog(
      message: '시간이 초과되었습니다.\n코인으로 이어하면 현재 레벨과 점수를 유지할 수 있어요.',
    ));
  }

  Future<void> _showFailDialog({String? message}) async {
    if (_isFailDialogShowing) return;
    if (!mounted) return;
    _isFailDialogShowing = true;
    final text = message ??
        '실패했습니다.\n코인으로 이어하면 현재 레벨과 점수를 유지한 채 다시 도전할 수 있어요.';
    final coins = await getGoldenCoins();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('게임 실패'),
        content: Text(
          text,
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'giveup'),
            child: const Text('포기'),
          ),
          if (coins >= 1)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'revive'),
              child: const Text('코인 1개로 이어하기'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    _isFailDialogShowing = false;
    if (choice == 'revive') {
      await setGoldenCoins(coins - 1);
      unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
      setState(() {
        _lastResult = '중앙에 가까울수록 높은 점수!';
      });
      _startRound();
      return;
    }
    _resetGame();
    setState(() {
      _lastResult = '실패 후 재시작! 다시 도전해보세요.';
    });
  }

  void _onTap() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();

    final diff = (_position - _targetCenter).abs();
    final maxDiff = _targetWidth / 2;
    if (diff > maxDiff) {
      setState(() {
        _lastResult = '중앙 밖에서 멈췄습니다. 실패!';
      });
      unawaited(_showFailDialog(
        message: '중앙에 표시된 영역 밖에서 멈췄습니다.\n코인으로 이어하면 현재 레벨과 점수를 유지할 수 있어요.',
      ));
      return;
    }

    int deltaScore;
    String message;

    if (diff <= _targetWidth * 0.25) {
      deltaScore = 150 + _level * 5;
      message = '완벽한 타이밍!';
    } else {
      deltaScore = 90 + _level * 4;
      message = '아주 좋아요!';
    }

    setState(() {
      _score += deltaScore;
      _lastResult = '$message (+$deltaScore점)';
      _level = (_level + 1).clamp(1, _maxLevel);
    });
    unawaited(_saveBestScoreAndSync());

    // 다음 라운드를 약간 쉬었다 시작
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _startRound();
    });
  }

  Future<void> _saveBestScoreAndSync() async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt(_bestScoreKey) ?? 0;
    if (_score <= prev) return;
    await prefs.setInt(_bestScoreKey, _score);
    if (!mounted) return;
    setState(() {
      _bestScore = _score;
    });
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
  }

  void _resetGame() {
    _timer?.cancel();
    setState(() {
      _position = 0;
      _running = false;
      _score = 0;
      _level = 1;
      _lastResult = '중앙에 가까울수록 높은 점수!';
    });
  }

  void _onBackPressed() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          title: const Text('완벽 타이밍'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _onBackPressed,
          ),
        ),
        body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoChip('레벨', '$_level'),
                  _infoChip('점수', '$_score'),
                  _infoChip('최고 점수', '$_bestScore'),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppTheme.cardShadowSubtle,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '게임 설명',
                      style: AppTheme.titleMedium.copyWith(color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '움직이는 표시가 중앙의 연한 영역에 올 때 화면을 탭해 보세요.\n'
                      '레벨이 올라갈수록 속도가 점점 빨라집니다.',
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.cardShadowSubtle,
                  ),
                  child: Column(
                    children: [
                      Text(
                        _lastResult,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Center(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final barWidth = constraints.maxWidth - 32;
                              final barHeight = 26.0;
                              final targetLeft =
                                  (barWidth * (_targetCenter - _targetWidth / 2)).clamp(0.0, barWidth);
                              final targetWidthPx =
                                  (barWidth * _targetWidth).clamp(30.0, barWidth);

                              final markerX =
                                  (barWidth * _position).clamp(0.0, barWidth);

                              return GestureDetector(
                                onTap: _onTap,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          width: barWidth,
                                          height: barHeight,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(999),
                                            color: AppTheme.surface,
                                            border: Border.all(
                                              color: AppTheme.primary.withOpacity(0.25),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: targetLeft,
                                          top: 2,
                                          bottom: 2,
                                          width: targetWidthPx,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(999),
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppTheme.primary.withOpacity(0.12),
                                                  AppTheme.primary.withOpacity(0.25),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: markerX - 10,
                                          top: -4,
                                          child: Container(
                                            width: 20,
                                            height: barHeight + 8,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(999),
                                              color: Colors.white,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.08),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                              border: Border.all(
                                                color: AppTheme.primary,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _running ? '지금! 중앙에 왔다고 느끼면 탭하세요.' : '화면을 탭해서 시작하거나, 중앙에 올 때 멈춰 보세요.',
                                      textAlign: TextAlign.center,
                                      style: AppTheme.bodyMedium.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const BannerAdBar(),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_running) {
                              _onTap();
                            } else {
                              _startRound();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(_running ? '지금 멈추기!' : '게임 시작하기'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: Column(
        children: [
          Text(
            label,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textMuted,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

