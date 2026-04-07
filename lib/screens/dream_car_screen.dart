import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/app_analytics.dart';
import '../api/api_config.dart';
import '../api/bff_profile_api.dart';
import '../api/remote_assets.dart';
import '../data/dream_car_models.dart';
import '../data/dream_car_prefs.dart';
import '../supabase/supabase_sync_service.dart';
import '../theme/app_theme.dart';
import 'attendance_screen.dart';

class DreamCarScreen extends StatefulWidget {
  const DreamCarScreen({super.key});

  @override
  State<DreamCarScreen> createState() => _DreamCarScreenState();
}

class _DreamCarScreenState extends State<DreamCarScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _brand; // 'hcompany' | 'kcompany'
  int _stage = 1;
  int? _startMs;
  int _coinBalance = 0;

  Timer? _tick;
  late AnimationController _celebrationController;

  @override
  void initState() {
    super.initState();
    AppAnalytics.screen('dream_car_screen');
    WidgetsBinding.instance.addObserver(this);
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshCoins());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadStartOnly());
    }
  }

  Future<void> _refreshCoins() async {
    final c = await getGoldenCoins();
    if (mounted) setState(() => _coinBalance = c);
  }

  Future<void> _loadStartOnly() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _startMs = prefs.getInt('startTime'));
    await _refreshCoins();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawBrand = prefs.getString(DreamCarPrefsKeys.brand);
    final normalizedBrand = _normalizeDreamCarBrand(rawBrand);
    if (normalizedBrand != null && normalizedBrand != rawBrand) {
      await prefs.setString(DreamCarPrefsKeys.brand, normalizedBrand);
    }
    if (!mounted) return;
    setState(() {
      _brand = normalizedBrand;
      _stage = (prefs.getInt(DreamCarPrefsKeys.stage) ?? 1)
          .clamp(1, DreamCarCatalog.maxStage);
      _startMs = prefs.getInt('startTime');
    });
    await _refreshCoins();
  }

  bool get _canUpgrade {
    if (_brand == null) return false;
    return DreamCarCatalog.canUpgradeWithCoins(_stage, _coinBalance);
  }

  double get _gaugeProgress =>
      DreamCarCatalog.coinGaugeProgressForNextUpgrade(_stage, _coinBalance);

  int get _coinsRemaining =>
      DreamCarCatalog.coinsRemainingForNextUpgrade(_stage, _coinBalance);

  Future<void> _setBrand(String brand) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DreamCarPrefsKeys.brand, brand);
    await prefs.setInt(DreamCarPrefsKeys.stage, 1);
    if (!mounted) return;
    setState(() {
      _brand = brand;
      _stage = 1;
    });
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
  }

  Future<void> _upgrade() async {
    if (!_canUpgrade || _brand == null) return;
    final remaining =
        await consumeCoinsIfPossible(DreamCarCatalog.coinsPerUpgrade);
    if (remaining == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '금연코인이 부족합니다. (${DreamCarCatalog.coinsPerUpgrade}코인 필요)',
            ),
          ),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final next = _stage + 1;
    await prefs.setInt(DreamCarPrefsKeys.stage, next);
    if (!mounted) return;
    setState(() {
      _stage = next;
      _coinBalance = remaining;
    });
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());

    unawaited(AppAnalytics.log('dream_car_upgrade', params: {
      'brand': _brand!,
      'stage_after': next,
    }));

    final nick =
        await BffProfileApi.readCachedDisplayNameForCurrentUser() ?? '나';
    if (!mounted) return;

    _celebrationController.forward(from: 0);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        });
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration_rounded,
                  size: 56, color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                '$nick의 차가 업그레이드 되었습니다!',
                textAlign: TextAlign.center,
                style: AppTheme.titleMedium.copyWith(height: 1.35),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmChangeBrand() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('브랜드 변경'),
        content: const Text(
          '브랜드를 바꾸면 차 단계가 1단계로 초기화됩니다. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _brand = null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(DreamCarPrefsKeys.brand);
    await prefs.setInt(DreamCarPrefsKeys.stage, 1);
    unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('나의 드림카'),
        actions: [
          if (_brand != null)
            IconButton(
              tooltip: '브랜드 변경',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: _confirmChangeBrand,
            ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: bottomInset + 24,
              ),
              child: _brand == null
                  ? _BrandPicker(onPick: _setBrand)
                  : _CarPanel(
                      brand: _brand!,
                      stage: _stage,
                      startMs: _startMs,
                      coinBalance: _coinBalance,
                      gaugeProgress: _gaugeProgress,
                      coinsRemaining: _coinsRemaining,
                      canUpgrade: _canUpgrade,
                      onUpgrade: _upgrade,
                    ),
            ),
          ),
          if (_brand != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _celebrationController,
                  builder: (context, child) {
                    final t = _celebrationController.value;
                    if (t <= 0.001) return const SizedBox.shrink();
                    return CustomPaint(
                      painter: _CelebrationPainter(progress: t),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandPicker extends StatelessWidget {
  const _BrandPicker({required this.onPick});

  final Future<void> Function(String brand) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(),
        const SizedBox(height: 16),
        Text(
          '먼저 브랜드를 선택해주세요',
          textAlign: TextAlign.center,
          style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        _BrandButton(
          label: 'H Company',
          color: const Color(0xFF002C5F),
          onTap: () => onPick('hcompany'),
        ),
        const SizedBox(height: 12),
        _BrandButton(
          label: 'K Company',
          color: const Color(0xFF05141F),
          onTap: () => onPick('kcompany'),
        ),
      ],
    );
  }
}

class _BrandButton extends StatelessWidget {
  const _BrandButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          child: Row(
            children: [
              Icon(Icons.directions_car_filled_rounded,
                  color: Colors.white.withValues(alpha: 0.95), size: 36),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _normalizeDreamCarBrand(String? brand) {
  final b = brand?.trim().toLowerCase();
  if (b == null || b.isEmpty) return null;
  if (b == 'hcompany' || b == 'hyundai') return 'hcompany';
  if (b == 'kcompany' || b == 'kia') return 'kcompany';
  return null;
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monetization_on_rounded,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '금연 코인을 모아 드림카를 단계별로 업그레이드해 보세요.',
                  style: AppTheme.titleMedium.copyWith(color: AppTheme.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarPanel extends StatelessWidget {
  const _CarPanel({
    required this.brand,
    required this.stage,
    required this.startMs,
    required this.coinBalance,
    required this.gaugeProgress,
    required this.coinsRemaining,
    required this.canUpgrade,
    required this.onUpgrade,
  });

  final String brand;
  final int stage;
  final int? startMs;
  final int coinBalance;
  final double gaugeProgress;
  final int coinsRemaining;
  final bool canUpgrade;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final assetKey = DreamCarCatalog.assetKey(brand, stage);
    final maxed = stage >= DreamCarCatalog.maxStage;
    final nf = NumberFormat.decimalPattern('ko_KR');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.cardShadowSubtle,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '단계 $stage / ${DreamCarCatalog.maxStage}',
                    style: AppTheme.labelMedium.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (startMs == null) ...[
                const SizedBox(height: 12),
                Text(
                  '메인 화면에서 금연 시작일이 설정되어 있어야 절약·코인 환전이 가능해요.',
                  style: AppTheme.labelMedium.copyWith(
                    fontSize: 12,
                    color: AppTheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '보유 금연코인',
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  RemoteAssetImage(
                    assetKey: 'scoin.png',
                    width: 28,
                    height: 28,
                    error: Icon(Icons.monetization_on_rounded,
                        color: AppTheme.primary, size: 28),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${nf.format(coinBalance)}개',
                    style: AppTheme.titleLarge.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '단계마다 ${nf.format(DreamCarCatalog.coinsPerUpgrade)}코인으로 업그레이드할 수 있어요. 출석·게임·메인에서 절약 금액 환전 등으로 코인을 모을 수 있습니다.',
                style: AppTheme.labelMedium.copyWith(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              if (!maxed) ...[
                Text(
                  '다음 단계까지 ${nf.format(DreamCarCatalog.coinsPerUpgrade)}코인',
                  style: AppTheme.labelMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: gaugeProgress.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: AppTheme.textMuted.withValues(alpha: 0.25),
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  canUpgrade
                      ? '업그레이드할 수 있어요!'
                      : '이번 단계까지 ${nf.format(coinsRemaining)}코인 더 모으면 돼요',
                  style: AppTheme.labelMedium.copyWith(
                    color: canUpgrade ? AppTheme.success : AppTheme.textSecondary,
                    fontWeight: canUpgrade ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ] else ...[
                Text(
                  '최대 ${DreamCarCatalog.maxStage}단계까지 모두 업그레이드했어요!',
                  style: AppTheme.labelMedium.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RemoteAssetImage(
                      assetKey: assetKey,
                      fit: BoxFit.contain,
                      error: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_car_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            ApiConfig.isConfigured
                                ? '이미지를 불러올 수 없어요\n서버에 $assetKey 를 올려주세요'
                                : '서버 연결이 필요해요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: (maxed || !canUpgrade) ? null : onUpgrade,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor:
                        AppTheme.textMuted.withValues(alpha: 0.3),
                  ),
                  child: Text(
                    maxed
                        ? '차를 최대로 업그레이드 시켰습니다.'
                        : (canUpgrade
                            ? '업그레이드 (${nf.format(DreamCarCatalog.coinsPerUpgrade)}코인)'
                            : '금연코인을 더 모아주세요'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 간단한 방사형 파티클 축하 이펙트
class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final rnd = math.Random(7);
    const n = 28;
    for (var i = 0; i < n; i++) {
      final baseAngle = (i / n) * math.pi * 2 + rnd.nextDouble() * 0.4;
      final dist = progress * (120 + rnd.nextDouble() * 180);
      final p = Offset(
        center.dx + math.cos(baseAngle) * dist,
        center.dy + math.sin(baseAngle) * dist * 0.85,
      );
      final colors = [
        const Color(0xFFFFD700),
        const Color(0xFFFF6B6B),
        const Color(0xFF4ECDC4),
        const Color(0xFFA855F7),
        const Color(0xFFFFA94D),
      ];
      final paint = Paint()
        ..color = colors[i % colors.length]
            .withValues(alpha: (1 - progress) * 0.85)
        ..style = PaintingStyle.fill;
      final r = (1 - progress) * 6 + 2;
      canvas.drawCircle(p, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
