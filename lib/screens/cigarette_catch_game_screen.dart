import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/remote_assets.dart';
import '../theme/app_theme.dart';
import '../ad_manager.dart';
import '../supabase/supabase_sync_service.dart';
import 'attendance_screen.dart';
import '../api/game_reward_helper.dart';
import '../api/game_sync_helper.dart';

/// 낙하 맞추기: 떨어지는 목표 2개를 시간차로 맞추는 게임. 1~100단계, 단계별 속도 증가, 점수·최종단계 기록.
class CigaretteCatchGameScreen extends StatefulWidget {
  const CigaretteCatchGameScreen({super.key});

  @override
  State<CigaretteCatchGameScreen> createState() => _CigaretteCatchGameScreenState();
}

class _CigaretteCatchGameScreenState extends State<CigaretteCatchGameScreen>
    with SingleTickerProviderStateMixin {
  static const String _bestStageKey = 'cigarette_catch_best_stage';
  static const String _bestScoreKey = 'cigarette_catch_best_score';

  final Random _random = Random();
  Timer? _timer;
  int _stage = 1;
  int _score = 0;
  int _bestStage = 0;
  int _bestScore = 0;
  bool _gameOver = false;
  bool _waitingStart = true;

  double _gameAreaWidth = 300;
  double _gameAreaHeight = 500;
  static const double _cigaretteWidth = 42;
  static const double _cigaretteHeight = 58;
  static const double _hitZoneHeight = 100;

  final List<_FallingCigarette> _cigarettes = [];
  List<String> _cigaretteAssets = const [];
  int _spawned = 0;
  static const int _cigarettesPerRound = 2;
  double _fallSpeed = 2;
  static const double _baseSpeed = 2;
  static const double _speedPerStage = 0.15;
  int _spawnDelayMs = 800;
  bool _isGameOverAdShowing = false;

  /// 맞춤 성공 시 탭 위치에 짧은 이펙트
  late AnimationController _hitFxController;
  Offset? _hitFxLocal;

  @override
  void initState() {
    super.initState();
    _hitFxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _hitFxLocal = null);
        }
      });
    _loadBest();
    _loadCigaretteAssets();
  }

  Future<void> _loadCigaretteAssets() async {
    try {
      final assets = await RemoteAssets.fetchCigarettePackKeys();
      if (!mounted) return;
      setState(() {
        _cigaretteAssets = assets;
      });
    } catch (_) {
      // 목록 실패 시 기존 fallback painter 사용
    }
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _bestStage = prefs.getInt(_bestStageKey) ?? 0;
        _bestScore = prefs.getInt(_bestScoreKey) ?? 0;
      });
    }
  }

  Future<void> _saveBest() async {
    if (_stage - 1 <= _bestStage) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestStageKey, _stage - 1);
    if (mounted) setState(() => _bestStage = _stage - 1);
  }

  Future<void> _saveBestScore() async {
    if (_score <= _bestScore) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestScoreKey, _score);
    if (mounted) setState(() => _bestScore = _score);
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    if (mounted) {
      unawaited(syncStatsThenClaimGameRewardWithSnackBar(
        context,
        game: 'cigarette_catch',
        proof: {'bestScore': _score},
      ));
    }
  }

  void _startGame() {
    setState(() {
      _waitingStart = false;
      _gameOver = false;
      _stage = 1;
      _score = 0;
      _cigarettes.clear();
      _spawned = 0;
      _fallSpeed = _baseSpeed + (_stage - 1) * _speedPerStage;
      _spawnDelayMs = (800 - (_stage - 1) * 6).clamp(200, 800);
      _isGameOverAdShowing = false;
    });
    _startLoop();
    // 실제 Stack 크기와 _gameArea* 가 맞은 뒤 스폰 (바깥 LayoutBuilder 값만 쓰면 좌표가 어긋날 수 있음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _waitingStart || _gameOver) return;
      _spawnNext();
    });
  }

  void _startLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _gameOver || _waitingStart) return;
      _update();
    });
  }

  void _update() {
    for (var i = _cigarettes.length - 1; i >= 0; i--) {
      final c = _cigarettes[i];
      c.y += _fallSpeed;
      if (c.y > _gameAreaHeight) {
        _cigarettes.removeAt(i);
        _onFallMiss();
        return;
      }
    }
    setState(() {});
  }

  void _spawnNext() {
    if (!mounted || _gameOver) return;
    if (_gameAreaWidth < _cigaretteWidth + 8 || _gameAreaHeight < _cigaretteHeight + _hitZoneHeight + 20) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _gameOver) return;
        _spawnNext();
      });
      return;
    }
    if (_spawned >= _cigarettesPerRound) {
      _spawned = 0;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted || _gameOver) return;
        setState(() {
          _stage = (_stage + 1).clamp(1, 100);
          _fallSpeed = _baseSpeed + (_stage - 1) * _speedPerStage;
          _spawnDelayMs = (800 - (_stage - 1) * 6).clamp(200, 800);
        });
        _spawnNext();
      });
      return;
    }
    final maxX = (_gameAreaWidth - _cigaretteWidth - 8)
        .clamp(0.0, double.infinity)
        .toDouble();
    final x = 4.0 + (maxX <= 0 ? 0.0 : _random.nextDouble() * maxX);
    final assetPath = _cigaretteAssets.isEmpty
        ? null
        : _cigaretteAssets[_random.nextInt(_cigaretteAssets.length)];
    // Stack 좌표계 상단(y=0) 위에서 등장 → 화면 안으로 자연스럽게 낙하
    _cigarettes.add(
      _FallingCigarette(
        x: x,
        y: -_cigaretteHeight - 4,
        assetPath: assetPath,
      ),
    );
    _spawned++;
    if (_spawned < _cigarettesPerRound) {
      Future.delayed(Duration(milliseconds: _spawnDelayMs), _spawnNext);
    }
    setState(() {});
  }

  void _onTap(Offset local) {
    if (_gameOver || _waitingStart) return;
    final hitZoneTop = _gameAreaHeight - _hitZoneHeight;
    // 담배와 맞춤 영역이 겹칠 때만 인정 (이전: 상단 y만 봐서 반쯤 들어온 경우 놓침)
    const padX = 32.0;
    const padY = 36.0;
    for (var i = 0; i < _cigarettes.length; i++) {
      final c = _cigarettes[i];
      final cigBottom = c.y + _cigaretteHeight;
      final overlapsZone = cigBottom > hitZoneTop && c.y < _gameAreaHeight;
      if (!overlapsZone) continue;
      final left = c.x - padX;
      final right = c.x + _cigaretteWidth + padX;
      final top = c.y - padY;
      final bottom = c.y + _cigaretteHeight + padY;
      if (local.dx >= left && local.dx <= right && local.dy >= top && local.dy <= bottom) {
        HapticFeedback.lightImpact();
        _cigarettes.removeAt(i);
        setState(() {
          _score += 10 + _stage;
          _hitFxLocal = local;
        });
        _hitFxController.forward(from: 0);
        unawaited(_saveBestScore());
        if (_cigarettes.isEmpty && _spawned >= _cigarettesPerRound) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted || _gameOver) return;
            setState(() {
              _spawned = 0;
              _stage = (_stage + 1).clamp(1, 100);
              _fallSpeed = _baseSpeed + (_stage - 1) * _speedPerStage;
              _spawnDelayMs = (800 - (_stage - 1) * 6).clamp(200, 800);
            });
            _spawnNext();
          });
        }
        return;
      }
    }
  }

  Future<void> _onFallMiss() async {
    _timer?.cancel();
    if (!mounted) return;
    final coins = await getGoldenCoins();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('게임 오버'),
        content: Text(
          coins >= 1
              ? '코인 1개를 사용하면 같은 단계에서 이어서 플레이할 수 있어요.'
              : '포기하고 결과를 확인할까요?\n(코인이 부족하면 이어하기를 할 수 없어요.)',
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
    if (choice == 'revive') {
      final remaining = await consumeCoinsIfPossible(1);
      if (remaining == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('코인이 부족하여 이어하기를 할 수 없습니다.')),
        );
        await _finalizeGameOver();
        return;
      }
      unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
      unawaitedSyncGameStatsToApiIfAvailable();
      setState(() {
        _gameOver = false;
        _cigarettes.clear();
        _spawned = 0;
        _isGameOverAdShowing = false;
      });
      _startLoop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _gameOver) return;
        _spawnNext();
      });
      return;
    }
    await _finalizeGameOver();
  }

  Future<void> _finalizeGameOver() async {
    _timer?.cancel();
    await _saveBest();
    await _saveBestScore();
    await SupabaseSyncService.pushLocalToRemoteIfEligible();
    unawaitedSyncGameStatsToApiIfAvailable();
    if (!mounted) return;
    setState(() => _gameOver = true);
    if (_isGameOverAdShowing) return;
    _isGameOverAdShowing = true;
    AdManager.showAd(onAdClosed: () {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hitFxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('낙하 맞추기'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    _infoChip('단계', '$_stage'),
                    _infoChip('점수', '$_score'),
                    _infoChip('최고 점수', '$_bestScore'),
                    _infoChip('최고 단계', '$_bestStage'),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppTheme.cardShadowSubtle,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          _waitingStart
                              ? '떨어지는 표시를\n맞는 타이밍에 탭하세요'
                              : _gameOver
                                  ? '게임 종료'
                                  : '아래 연한 영역에 들어왔을 때 탭!',
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, inner) {
                              const marginH = 16.0;
                              const marginV = 8.0;
                              final playW = (inner.maxWidth - marginH * 2)
                                  .clamp(_cigaretteWidth + 8, double.infinity);
                              final playH = (inner.maxHeight - marginV * 2)
                                  .clamp(_hitZoneHeight + _cigaretteHeight + 24, double.infinity);
                              // Stack 좌표계와 낙하 판정이 항상 일치하도록(바깥 추정값 사용 금지)
                              _gameAreaWidth = playW;
                              _gameAreaHeight = playH;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: marginH,
                                  vertical: marginV,
                                ),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    width: playW,
                                    height: playH,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppTheme.primary.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Stack(
                                        clipBehavior: Clip.hardEdge,
                                        children: [
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            height: _hitZoneHeight,
                                            child: IgnorePointer(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      AppTheme.primary.withValues(alpha: 0.06),
                                                      AppTheme.primary.withValues(alpha: 0.16),
                                                    ],
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '맞출 영역',
                                                  style: AppTheme.bodyMedium.copyWith(
                                                    color: AppTheme.primaryDark,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          for (final c in _cigarettes)
                                            Positioned(
                                              left: c.x,
                                              top: c.y,
                                              width: _cigaretteWidth,
                                              height: _cigaretteHeight,
                                              child: _buildCigarette(c.assetPath),
                                            ),
                                          Positioned.fill(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.translucent,
                                              onTapDown: (d) => _onTap(d.localPosition),
                                              child: const SizedBox.expand(),
                                            ),
                                          ),
                                          if (_hitFxLocal != null)
                                            Positioned(
                                              left: _hitFxLocal!.dx - 44,
                                              top: _hitFxLocal!.dy - 44,
                                              child: IgnorePointer(
                                                child: AnimatedBuilder(
                                                  animation: _hitFxController,
                                                  builder: (context, _) => _HitTapBurst(
                                                    progress: _hitFxController.value,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_waitingStart)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: ElevatedButton.icon(
                              onPressed: _startGame,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('게임 시작'),
                            ),
                          )
                        else if (_gameOver)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _waitingStart = true;
                                      _gameOver = false;
                                    });
                                  },
                                  child: const Text('처음 화면으로'),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _startGame,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('다시 도전'),
                                ),
                              ],
                            ),
                          )
                        else
                          const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          Text(value, style: AppTheme.titleMedium.copyWith(color: AppTheme.primary)),
        ],
      ),
    );
  }

  Widget _buildCigarette(String? assetPath) {
    if (assetPath == null) {
      return CustomPaint(
        size: const Size(_cigaretteWidth, _cigaretteHeight),
        painter: _CigarettePainter(),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: RemoteAssetImage(
        assetKey: assetPath,
        fit: BoxFit.contain,
        width: _cigaretteWidth,
        height: _cigaretteHeight,
        error: CustomPaint(
          size: const Size(_cigaretteWidth, _cigaretteHeight),
          painter: _CigarettePainter(),
        ),
      ),
    );
  }
}

class _FallingCigarette {
  double x, y;
  String? assetPath;
  _FallingCigarette({required this.x, required this.y, this.assetPath});
}

/// 맞춤 순간 탭 위 펄스 + 볼트 아이콘
class _HitTapBurst extends StatelessWidget {
  const _HitTapBurst({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    final fade = 1.0 - t;
    final scale = 0.45 + t * 0.95;
    return Opacity(
      opacity: fade,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.45 * fade),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              Container(
                width: 64 + 24 * t,
                height: 64 + 24 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.5 * fade * (1 - t * 0.7)),
                    width: 2,
                  ),
                ),
              ),
              Icon(
                Icons.bolt_rounded,
                size: 42,
                color: AppTheme.primary.withValues(alpha: 0.85 + 0.15 * fade),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CigarettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width - r, size.height), Radius.circular(r));
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width - r, r), r, Paint()..color = Colors.orange.shade700);
    canvas.drawRect(Rect.fromLTWH(size.width - r - 2, 0, 4, size.height), Paint()..color = Colors.brown.shade300);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
