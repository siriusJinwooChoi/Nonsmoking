import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../ad_manager.dart';

/// 담배맞추기: 떨어지는 담배 2개를 시간차로 맞추는 게임. 1~100단계, 단계별 속도 증가, 점수·최종단계 기록.
class CigaretteCatchGameScreen extends StatefulWidget {
  const CigaretteCatchGameScreen({super.key});

  @override
  State<CigaretteCatchGameScreen> createState() => _CigaretteCatchGameScreenState();
}

class _CigaretteCatchGameScreenState extends State<CigaretteCatchGameScreen> {
  static const String _bestStageKey = 'cigarette_catch_best_stage';

  final Random _random = Random();
  Timer? _timer;
  int _stage = 1;
  int _score = 0;
  int _bestStage = 0;
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
  double _nextSpawnY = 0;
  double _fallSpeed = 2;
  static const double _baseSpeed = 2;
  static const double _speedPerStage = 0.15;
  int _spawnDelayMs = 800;
  bool _roundInProgress = false;
  bool _isGameOverAdShowing = false;

  @override
  void initState() {
    super.initState();
    _loadBest();
    _loadCigaretteAssets();
  }

  Future<void> _loadCigaretteAssets() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final assets = manifest.keys
          .where((k) {
            if (!k.startsWith('assets/cigarettes/')) return false;
            final lower = k.toLowerCase();
            return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg');
          })
          .toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _cigaretteAssets = assets;
      });
    } catch (_) {
      // 에셋 로드 실패 시 기존 fallback painter 사용
    }
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _bestStage = prefs.getInt(_bestStageKey) ?? 0);
  }

  Future<void> _saveBest() async {
    if (_stage - 1 <= _bestStage) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestStageKey, _stage - 1);
    if (mounted) setState(() => _bestStage = _stage - 1);
  }

  void _startGame() {
    setState(() {
      _waitingStart = false;
      _gameOver = false;
      _stage = 1;
      _score = 0;
      _cigarettes.clear();
      _spawned = 0;
      _roundInProgress = true;
      _fallSpeed = _baseSpeed + (_stage - 1) * _speedPerStage;
      _spawnDelayMs = (800 - (_stage - 1) * 6).clamp(200, 800);
      _isGameOverAdShowing = false;
    });
    _spawnNext();
    _startLoop();
  }

  void _startLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _gameOver || _waitingStart) return;
      _update();
    });
  }

  void _update() {
    final hitZoneTop = _gameAreaHeight - _hitZoneHeight;
    for (var i = _cigarettes.length - 1; i >= 0; i--) {
      final c = _cigarettes[i];
      c.y += _fallSpeed;
      if (c.y > _gameAreaHeight) {
        _cigarettes.removeAt(i);
        _endGame();
        return;
      }
    }
    setState(() {});
  }

  void _spawnNext() {
    if (!mounted || _gameOver) return;
    if (_spawned >= _cigarettesPerRound) {
      _spawned = 0;
      _roundInProgress = false;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted || _gameOver) return;
        setState(() {
          _stage = (_stage + 1).clamp(1, 100);
          _fallSpeed = _baseSpeed + (_stage - 1) * _speedPerStage;
          _spawnDelayMs = (800 - (_stage - 1) * 6).clamp(200, 800);
          _roundInProgress = true;
        });
        _spawnNext();
      });
      return;
    }
    final x = 20 + _random.nextDouble() * (_gameAreaWidth - 40 - _cigaretteWidth);
    final assetPath = _cigaretteAssets.isEmpty
        ? null
        : _cigaretteAssets[_random.nextInt(_cigaretteAssets.length)];
    _cigarettes.add(_FallingCigarette(x: x, y: -_cigaretteHeight, assetPath: assetPath));
    _spawned++;
    if (_spawned < _cigarettesPerRound) {
      Future.delayed(Duration(milliseconds: _spawnDelayMs), _spawnNext);
    }
    setState(() {});
  }

  void _onTap(Offset local) {
    if (_gameOver || _waitingStart) return;
    final hitZoneTop = _gameAreaHeight - _hitZoneHeight;
    for (var i = 0; i < _cigarettes.length; i++) {
      final c = _cigarettes[i];
      if (c.y < hitZoneTop || c.y > _gameAreaHeight) continue;
      final cx = c.x + _cigaretteWidth / 2;
      final cy = c.y + _cigaretteHeight / 2;
      if ((local.dx - cx).abs() < 35 && (local.dy - cy).abs() < 35) {
        HapticFeedback.lightImpact();
        _cigarettes.removeAt(i);
        setState(() => _score += 10 + _stage);
        if (_cigarettes.isEmpty && _spawned >= _cigarettesPerRound) {
          _roundInProgress = false;
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted || _gameOver) return;
            setState(() {
              _spawned = 0;
              _stage = (_stage + 1).clamp(1, 100);
              _fallSpeed = _baseSpeed + (_stage - 1) * _speedPerStage;
              _spawnDelayMs = (800 - (_stage - 1) * 6).clamp(200, 800);
              _roundInProgress = true;
            });
            _spawnNext();
          });
        }
        return;
      }
    }
  }

  void _endGame() async {
    _timer?.cancel();
    await _saveBest();
    if (!mounted) return;
    setState(() => _gameOver = true);
    if (_isGameOverAdShowing) return;
    _isGameOverAdShowing = true;
    AdManager.showAd(onAdClosed: () {});
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
        title: const Text('담배맞추기'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: LayoutBuilder(
        builder: (context, constraints) {
          _gameAreaWidth = constraints.maxWidth - 32;
          _gameAreaHeight = constraints.maxHeight - 220;
          _gameAreaHeight = _gameAreaHeight.clamp(260.0, 520.0);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoChip('단계', '$_stage'),
                    _infoChip('점수', '$_score'),
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
                              ? '떨어지는 담배를\n맞는 타이밍에 탭하세요'
                              : _gameOver
                                  ? '게임 종료'
                                  : '아래 연한 영역에 들어왔을 때 탭!',
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: GestureDetector(
                            onTapDown: (d) => _onTap(d.localPosition),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    height: _hitZoneHeight,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            AppTheme.primary.withOpacity(0.06),
                                            AppTheme.primary.withOpacity(0.16),
                                          ],
                                        ),
                                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
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
                                  for (final c in _cigarettes)
                                    Positioned(
                                      left: c.x,
                                      top: c.y,
                                      width: _cigaretteWidth,
                                      height: _cigaretteHeight,
                                      child: _buildCigarette(c.assetPath),
                                    ),
                                ],
                              ),
                            ),
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
          );
        },
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
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => CustomPaint(
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
