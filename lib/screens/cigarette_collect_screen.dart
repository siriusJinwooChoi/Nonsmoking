import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'cigarette_catalog_screen.dart';
import 'attendance_screen.dart';
import '../supabase/supabase_sync_service.dart';
import '../notifications/daily_reminder_worker.dart';

/// 담배 수집 게임 화면
class CigaretteCollectScreen extends StatefulWidget {
  const CigaretteCollectScreen({super.key});

  @override
  State<CigaretteCollectScreen> createState() => _CigaretteCollectScreenState();
}

class _CigaretteCollectScreenState extends State<CigaretteCollectScreen>
    with SingleTickerProviderStateMixin {
  /// 수집 가능 시간대: 09:00~09:20, 12:00~12:20, 18:00~18:20, 22:00~22:20
  static const List<({int startHour, int startMinute})> _collectionWindows = [
    (startHour: 9, startMinute: 0),
    (startHour: 12, startMinute: 0),
    (startHour: 18, startMinute: 0),
    (startHour: 22, startMinute: 0),
  ];
  static const int _windowMinutes = 20;
  static const String _lastCollectionWindowKey = 'last_collection_window';
  static const String _sessionWindowKey = 'cigarette_collect_session_window';
  static const String _sessionAssetKey = 'cigarette_collect_session_asset';
  static const String _sessionAttemptsKey = 'cigarette_collect_session_attempts';
  static const int _coinsPerAttempt = 2;

  static final _random = Random();
  static const String _collectedKey = 'collected_cigarette_assets';
  static const double _successProbability = 0.10;
  static const int _maxAttempts = 5;

  List<String> _cigaretteAssets = const [];
  String? _currentAsset;
  int _attempts = 0;
  bool _caught = false;
  bool _disappeared = false;
  String _status = '지포라이터를 눌러 담배 수집을 시작하세요!';
  bool _loadingAssets = true;
  /// 현재 시간이 수집 가능 구간인지, 해당 구간을 이미 사용했는지
  bool _isInCollectionWindow = false;
  bool _hasUsedCurrentWindow = false;
  String? _currentWindowId;

  bool _showEffect = false;
  bool _effectSuccess = false;
  bool _pressingButton = false;
  double _pressProgress = 0.0;
  Timer? _pressTimer;
  Timer? _windowTimer;

  late AnimationController _effectController;

  @override
  void initState() {
    super.initState();
    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    unawaited(maybeNotifyCigaretteCollectionWindowOpened());
    _loadAssets();
    _windowTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_cigaretteAssets.isNotEmpty) {
        unawaited(maybeNotifyCigaretteCollectionWindowOpened());
        _loadWindowState(_cigaretteAssets);
      }
    });
  }

  /// 현재 시각이 속한 수집 가능 구간 ID (예: "2025-03-09-0900"). 없으면 null.
  static String? _getWindowIdFor(DateTime now) {
    final y = now.year;
    final m = now.month;
    final d = now.day;
    for (final w in _collectionWindows) {
      final start = DateTime(y, m, d, w.startHour, w.startMinute);
      final end = start.add(const Duration(minutes: _windowMinutes));
      if (!now.isBefore(start) && now.isBefore(end)) {
        final hh = w.startHour.toString().padLeft(2, '0');
        final mm = w.startMinute.toString().padLeft(2, '0');
        return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}-$hh$mm';
      }
    }
    return null;
  }

  /// 수집 가능 시간대 상태 + 같은 시간대 내 담배갑·시도 횟수 복원
  Future<void> _loadWindowState(List<String> assets) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUsed = prefs.getString(_lastCollectionWindowKey);
    final sessionWindow = prefs.getString(_sessionWindowKey);
    final sessionAsset = prefs.getString(_sessionAssetKey);
    final sessionAttempts = prefs.getInt(_sessionAttemptsKey) ?? 0;
    if (!mounted) return;
    final now = DateTime.now();
    final windowId = _getWindowIdFor(now);
    final isInWindow = windowId != null;
    final hasUsed = isInWindow && lastUsed == windowId;
    String? asset;
    int attempts = 0;
    if (isInWindow && !hasUsed && assets.isNotEmpty) {
      if (sessionWindow == windowId &&
          sessionAsset != null &&
          sessionAsset.isNotEmpty &&
          assets.contains(sessionAsset)) {
        asset = sessionAsset;
        attempts = sessionAttempts.clamp(0, _maxAttempts);
      } else {
        asset = assets[_random.nextInt(assets.length)];
        attempts = 0;
        await prefs.setString(_sessionWindowKey, windowId);
        await prefs.setString(_sessionAssetKey, asset);
        await prefs.setInt(_sessionAttemptsKey, 0);
      }
    }
    if (!mounted) return;
    setState(() {
      _currentWindowId = windowId;
      _isInCollectionWindow = isInWindow;
      _hasUsedCurrentWindow = hasUsed;
      if (isInWindow && !hasUsed && assets.isNotEmpty) {
        _currentAsset = asset;
        _attempts = attempts;
        if (attempts > 0) {
          _caught = false;
          _disappeared = false;
          _status = '지포라이터를 눌러 담배 수집을 시작하세요!';
        }
      }
    });
  }

  /// 현재 시간대 세션 저장 (다른 메뉴 갔다 와도 담배갑·시도 횟수 유지)
  Future<void> _persistSession() async {
    final wid = _currentWindowId;
    final asset = _currentAsset;
    if (wid == null || asset == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionWindowKey, wid);
    await prefs.setString(_sessionAssetKey, asset);
    await prefs.setInt(_sessionAttemptsKey, _attempts);
  }

  /// assets/cigarettes/ 폴더 내 이미지 목록을 AssetManifest에서 불러옵니다.
  /// 이미지를 바꾼 경우 앱을 완전히 다시 빌드(flutter run)해야 반영됩니다.
  Future<void> _loadAssets() async {
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
        _currentAsset = assets.isNotEmpty ? assets[_random.nextInt(assets.length)] : null;
        _loadingAssets = false;
        if (_currentAsset == null) {
          _status = '담배갑 이미지가 없습니다. assets/cigarettes 폴더를 확인해 주세요.';
        }
      });
      await _loadWindowState(assets);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAssets = false;
        _currentAsset = null;
        _status = '담배갑 이미지를 불러오지 못했습니다. assets 설정을 확인해 주세요.';
      });
    }
  }

  @override
  void dispose() {
    _pressTimer?.cancel();
    _windowTimer?.cancel();
    _effectController.dispose();
    super.dispose();
  }

  Future<void> _triggerAttempt() async {
    if (_loadingAssets || _currentAsset == null) return;
    if (_caught || _disappeared) return;
    if (_attempts >= _maxAttempts) return;
    if (!_isInCollectionWindow || _hasUsedCurrentWindow) return;

    final coins = await getGoldenCoins();
    if (coins < _coinsPerAttempt) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('금연코인이 부족합니다. (1회 시도당 2코인 필요)'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    await setGoldenCoins(coins - _coinsPerAttempt);
    if (!mounted) return;

    setState(() => _attempts++);

    final success = _random.nextDouble() < _successProbability;
    if (success) {
      setState(() {
        _caught = true;
        _status = '수집에 성공했습니다!';
        _effectSuccess = true;
        _showEffect = true;
      });
      _persistCollected();
      _markWindowUsed();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('수집에 성공했습니다!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.primaryDark,
        ),
      );
    } else {
      if (_attempts >= _maxAttempts) {
        setState(() {
          _disappeared = true;
          _status = '다음 기회에 도전해보세요.';
          _effectSuccess = false;
          _showEffect = true;
        });
        _markWindowUsed();
      } else {
        setState(() {
          _status = '수집에 실패했습니다. 다시 한 번 시도해 보세요. ($_attempts/$_maxAttempts)';
          _effectSuccess = false;
          _showEffect = true;
        });
        await _persistSession();
      }
    }

    _effectController
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _showEffect = false);
      });
  }

  Future<void> _persistCollected() async {
    final asset = _currentAsset;
    if (asset == null) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_collectedKey) ?? <String>[];
    final set = list.toSet()..add(asset);
    await prefs.setStringList(_collectedKey, set.toList()..sort());
    await SupabaseSyncService.pushLocalToRemoteIfEligible();
  }

  /// 이번 수집 구간 사용 완료 처리 (성공 또는 5번 실패 시)
  Future<void> _markWindowUsed() async {
    final wid = _currentWindowId;
    if (wid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCollectionWindowKey, wid);
    await prefs.remove(_sessionWindowKey);
    await prefs.remove(_sessionAssetKey);
    await prefs.remove(_sessionAttemptsKey);
    if (!mounted) return;
    setState(() => _hasUsedCurrentWindow = true);
  }

  void _openCatalog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CigaretteCatalogScreen()),
    );
  }

  /// 수집 가능 시간 칩 (한 화면에 들어가도록 컴팩트하게)
  Widget _timeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 1),
      ),
      child: Text(
        label,
        style: AppTheme.bodyMedium.copyWith(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _onPressStart() {
    if (_loadingAssets || _currentAsset == null) return;
    if (_caught || _disappeared) return;
    if (_attempts >= _maxAttempts) return;
    if (!_isInCollectionWindow || _hasUsedCurrentWindow) return;
    _pressTimer?.cancel();
    setState(() {
      _pressingButton = true;
      _pressProgress = 0.0;
    });
    _pressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_pressingButton) {
        timer.cancel();
        return;
      }
      setState(() {
        _pressProgress += 0.025; // 50ms × 40틱 = 2초
        if (_pressProgress >= 1.0) {
          _pressProgress = 1.0;
          _pressingButton = false;
          timer.cancel();
          _triggerAttempt();
        }
      });
    });
  }

  void _onPressEnd() {
    if (!_pressingButton) return;
    _pressTimer?.cancel();
    setState(() {
      _pressingButton = false;
      _pressProgress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('담배 컬렉션'),
        actions: [
          IconButton(
            tooltip: '도감',
            icon: const Icon(Icons.collections_bookmark_rounded),
            onPressed: _openCatalog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.surfaceCard,
                      AppTheme.surfaceCard,
                      AppTheme.primary.withOpacity(0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    ...AppTheme.cardShadowSubtle,
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '여러 종류의 담배를 수집해보세요.',
                      style: AppTheme.titleMedium.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '지포라이터를 눌러 수집에 성공해보세요.',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '담배 수집 시 1회 시도할 때마다 금연코인 2개가\n소모됩니다.',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.surfaceCard,
                            AppTheme.surfaceCard,
                            Colors.white,
                            AppTheme.primary.withOpacity(0.04),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          ...AppTheme.cardShadowSubtle,
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: AppTheme.primary.withOpacity(0.12),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: _loadingAssets
                                  ? const CircularProgressIndicator()
                                  : !_isInCollectionWindow
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.schedule_rounded, size: 44, color: AppTheme.textMuted),
                                            const SizedBox(height: 10),
                                            Text(
                                              '현재는 담배를 수집할 수 있는 시간이\n아닙니다.',
                                              textAlign: TextAlign.center,
                                              style: AppTheme.titleMedium.copyWith(
                                                color: AppTheme.textPrimary,
                                                height: 1.3,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              '수집 가능 시간',
                                              style: AppTheme.bodyMedium.copyWith(
                                                color: AppTheme.textMuted,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              alignment: WrapAlignment.center,
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                _timeChip('09:00~09:20'),
                                                _timeChip('12:00~12:20'),
                                                _timeChip('18:00~18:20'),
                                                _timeChip('22:00~22:20'),
                                              ],
                                            ),
                                          ],
                                        )
                                      : _hasUsedCurrentWindow
                                          ? Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.check_circle_outline_rounded, size: 44, color: AppTheme.primary),
                                                const SizedBox(height: 10),
                                                Text(
                                                  '이번 수집 가능 시간을 이미 사용했습니다.',
                                                  textAlign: TextAlign.center,
                                                  style: AppTheme.titleMedium.copyWith(
                                                    color: AppTheme.textPrimary,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '다음 수집 시간(09:00, 12:00, 18:00, 22:00)을 이용해 주세요.',
                                                  textAlign: TextAlign.center,
                                                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted, fontSize: 11),
                                                ),
                                              ],
                                            )
                                      : !_disappeared
                                      ? Align(
                                          alignment: Alignment.topCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: AnimatedScale(
                                              scale: _showEffect
                                                  ? (_effectSuccess ? 1.05 : 0.95)
                                                  : 1.0,
                                              duration: const Duration(milliseconds: 200),
                                              child: AnimatedOpacity(
                                                duration: const Duration(milliseconds: 200),
                                                opacity: _disappeared ? 0 : 1,
                                                child: _currentAsset == null
                                                    ? const Icon(
                                                        Icons.image_not_supported_rounded,
                                                        size: 80,
                                                        color: AppTheme.textMuted,
                                                      )
                                                    : SizedBox(
                                                        height: 150,
                                                        child: Image.asset(
                                                          _currentAsset!,
                                                          fit: BoxFit.contain,
                                                          errorBuilder: (_, __, ___) => const Icon(
                                                            Icons.image_not_supported_rounded,
                                                            size: 80,
                                                            color: AppTheme.textMuted,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.local_fire_department_rounded,
                                          size: 80,
                                          color: AppTheme.textMuted,
                                        ),
                            ),
                          ),
                          if (!_caught && !_disappeared && _isInCollectionWindow && !_hasUsedCurrentWindow)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: GestureDetector(
                                onTapDown: (_) => _onPressStart(),
                                onTapUp: (_) => _onPressEnd(),
                                onTapCancel: _onPressEnd,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _status,
                                      textAlign: TextAlign.center,
                                      style: AppTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _caught
                                          ? '다음 기회에 또 도전해보세요.'
                                          : _disappeared
                                              ? ''
                                              : '남은 시도: ${_maxAttempts - _attempts}회',
                                      textAlign: TextAlign.center,
                                      style: AppTheme.bodyMedium.copyWith(
                                        color: _caught
                                            ? AppTheme.success
                                            : _disappeared
                                                ? AppTheme.textMuted
                                                : AppTheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    if (_pressingButton) ...[
                                      Text(
                                        '수집중...',
                                        style: AppTheme.bodyMedium.copyWith(
                                          fontSize: 13,
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: 120,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: _pressProgress,
                                            minHeight: 4,
                                            backgroundColor: AppTheme.textMuted.withOpacity(0.2),
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    AnimatedScale(
                                      scale: _pressingButton ? 0.94 : 1.0,
                                      duration: const Duration(milliseconds: 120),
                                      child: Lottie.asset(
                                        'assets/lottie/zippo.json',
                                        width: 128,
                                        height: 128,
                                        fit: BoxFit.contain,
                                        repeat: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_showEffect)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: FadeTransition(
                            opacity:
                                Tween<double>(begin: 0.0, end: 1.0).animate(_effectController),
                            child: Center(
                              child: Container(
                                width: 260,
                                height: 260,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: _effectSuccess
                                        ? [
                                            AppTheme.success.withOpacity(0.35),
                                            AppTheme.success.withOpacity(0.05),
                                            Colors.transparent,
                                          ]
                                        : [
                                            AppTheme.error.withOpacity(0.3),
                                            AppTheme.error.withOpacity(0.05),
                                            Colors.transparent,
                                          ],
                                    stops: const [0.0, 0.55, 1.0],
                                  ),
                                ),
                                child: _effectSuccess
                                    ? Center(
                                        child: ScaleTransition(
                                          scale: Tween<double>(begin: 0.8, end: 1.1)
                                              .animate(CurvedAnimation(
                                            parent: _effectController,
                                            curve: Curves.elasticOut,
                                          )),
                                          child: Container(
                                            width: 80,
                                            height: 80,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                            ),
                                            child: Icon(
                                              Icons.emoji_events_rounded,
                                              color: AppTheme.success,
                                              size: 42,
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

