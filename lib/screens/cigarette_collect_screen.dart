import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_config.dart';
import '../api/remote_assets.dart';
import '../data/cigarette_collection_prefs.dart';
import '../theme/app_theme.dart';
import 'attendance_screen.dart' show consumeCoinsIfPossible;
import 'cigarette_catalog_screen.dart';
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
  /// `last_collection_window` 와 같은 구간에서 성공/실패(5회 소진) 구분용
  static const String _lastWindowOutcomeKey = 'cigarette_collect_window_outcome_v1';
  static const String _sessionWindowKey = 'cigarette_collect_session_window';
  static const String _sessionAssetKey = 'cigarette_collect_session_asset';
  static const String _sessionAttemptsKey = 'cigarette_collect_session_attempts';
  static const int _coinsPerAttempt = 2;

  static final _random = Random();
  static const double _successProbability = 0.10;
  static const int _maxAttempts = 5;

  List<String> _cigaretteAssets = const [];
  String? _currentAsset;
  int _attempts = 0;
  bool _caught = false;
  bool _disappeared = false;
  String _status = '지포라이터를 눌러 도감 수집을 시작하세요!';
  bool _loadingAssets = true;
  /// 현재 시간이 수집 가능 구간인지, 해당 구간을 이미 사용했는지
  bool _isInCollectionWindow = false;
  bool _hasUsedCurrentWindow = false;
  /// 이번 시간대가 이미 끝났을 때 성공으로 끝났는지(null 이면 prefs 없음·구버전)
  bool? _lastUsedWindowCollected;
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
    unawaited(_bootstrapFastWindowState());
    _loadAssets();
    // 정각 진입 직후 수집 가능 상태가 늦게 보이는 현상을 줄이기 위해 짧은 주기로 갱신
    _windowTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_cigaretteAssets.isNotEmpty) {
        unawaited(maybeNotifyCigaretteCollectionWindowOpened());
        _loadWindowState(_cigaretteAssets);
      }
    });
  }

  /// 서버 목록 응답 전에, 이전 세션 담배갑 정보를 즉시 복원해 첫 화면 체감 지연을 줄인다.
  Future<void> _bootstrapFastWindowState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final now = DateTime.now();
    final windowId = _getWindowIdFor(now);
    final isInWindow = windowId != null;
    final lastUsed = prefs.getString(_lastCollectionWindowKey);
    final hasUsed = isInWindow && lastUsed == windowId;
    final sessionWindow = prefs.getString(_sessionWindowKey);
    final sessionAsset = prefs.getString(_sessionAssetKey);
    final sessionAttempts = prefs.getInt(_sessionAttemptsKey) ?? 0;
    final canRestoreSessionAsset = isInWindow &&
        !hasUsed &&
        sessionWindow == windowId &&
        sessionAsset != null &&
        sessionAsset.isNotEmpty;
    setState(() {
      _currentWindowId = windowId;
      _isInCollectionWindow = isInWindow;
      _hasUsedCurrentWindow = hasUsed;
      if (canRestoreSessionAsset) {
        _currentAsset = sessionAsset;
        _attempts = sessionAttempts.clamp(0, _maxAttempts);
        _loadingAssets = false;
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
    bool? usedOutcome;
    if (hasUsed) {
      final raw = prefs.getString(_lastWindowOutcomeKey);
      if (raw != null) {
        final sep = raw.indexOf('|');
        if (sep > 0 && sep < raw.length - 1) {
          final id = raw.substring(0, sep);
          final tag = raw.substring(sep + 1);
          if (id == windowId) {
            usedOutcome = tag == 'success';
          }
        }
      }
    }
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
      _lastUsedWindowCollected = hasUsed ? usedOutcome : null;
      if (isInWindow && !hasUsed && assets.isNotEmpty) {
        _currentAsset = asset;
        _attempts = attempts;
        if (attempts > 0) {
          _caught = false;
          _disappeared = false;
          _status = '지포라이터를 눌러 도감 수집을 시작하세요!';
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

  /// 서버 `GET /v1/assets/cigarettes` + `/static/cigarettes/*` 이미지.
  Future<void> _loadAssets() async {
    try {
      final assets = await RemoteAssets.fetchCigarettePackKeysCached();

      String? picked;
      var precacheOrder = assets;
      if (assets.isNotEmpty) {
        picked = assets[_random.nextInt(assets.length)];
        precacheOrder = <String>[
          picked,
          ...assets.where((k) => k != picked),
        ];
      }
      // 첫 진입 체감 개선: 첫 후보 담배갑 1장을 먼저 디코딩해 두고 화면에 노출한다.
      if (_currentAsset == null && picked != null && mounted) {
        await RemoteAssets.precacheFirstCigarettePackImages(
          context,
          [picked],
          count: 1,
          thumbnailDecodeWidth: 480,
        ).timeout(const Duration(milliseconds: 900), onTimeout: () {});
      }
      if (!mounted) return;
      setState(() {
        _cigaretteAssets = assets;
        _currentAsset = _currentAsset ?? picked;
        _loadingAssets = false;
        if (_currentAsset == null) {
          _status = ApiConfig.isConfigured
              ? '도감 이미지 목록이 비어 있거나 서버에서 불러오지 못했습니다.'
              : '서버 주소(API_BASE_URL)가 없어 이미지를 불러올 수 없습니다.';
        }
      });
      // 수집 화면 메인 이미지(memCacheWidth 480)와 맞춰 precache; UI는 목록 수신 직후 연다.
      const collectThumbW = 480;
      const firstBatch = 12;
      if (precacheOrder.isNotEmpty && mounted) {
        unawaited(
          RemoteAssets.precacheFirstCigarettePackImages(
            context,
            precacheOrder,
            count: firstBatch,
            thumbnailDecodeWidth: collectThumbW,
          ),
        );
        RemoteAssets.precacheRemainingCigarettePackImagesBackground(
          context,
          precacheOrder,
          startIndex: firstBatch,
          thumbnailDecodeWidth: collectThumbW,
        );
      }
      await _loadWindowState(assets);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAssets = false;
        _currentAsset = null;
        _status = '도감 이미지를 불러오지 못했습니다. 네트워크를 확인해 주세요.';
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

    final remainingCoins = await consumeCoinsIfPossible(_coinsPerAttempt);
    if (remainingCoins == null) {
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
      await _persistCollected();
      await _markWindowUsed(collectedSuccessfully: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('수집에 성공했습니다!'),
          duration: const Duration(seconds: 3),
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
        await _markWindowUsed(collectedSuccessfully: false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('수집에 실패했습니다. 이번 시간대의 기회를 모두 사용했어요.'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.error,
          ),
        );
      } else {
        setState(() {
          _status = '수집에 실패했습니다. 다시 한 번 시도해 보세요. ($_attempts/$_maxAttempts)';
          _effectSuccess = false;
          _showEffect = true;
        });
        await _persistSession();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('수집에 실패했습니다. 다시 시도해 주세요. ($_attempts/$_maxAttempts)'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.error,
          ),
        );
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
    await CigaretteCollectionPrefs.incrementCount(prefs, asset);
    await SupabaseSyncService.pushLocalToRemoteIfEligible();
  }

  /// 이번 수집 구간 사용 완료 처리 (성공 또는 5번 실패 시)
  Future<void> _markWindowUsed({required bool collectedSuccessfully}) async {
    final wid = _currentWindowId;
    if (wid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCollectionWindowKey, wid);
    await prefs.setString(
      _lastWindowOutcomeKey,
      '$wid|${collectedSuccessfully ? 'success' : 'fail'}',
    );
    await prefs.remove(_sessionWindowKey);
    await prefs.remove(_sessionAssetKey);
    await prefs.remove(_sessionAttemptsKey);
    if (!mounted) return;
    setState(() {
      _hasUsedCurrentWindow = true;
      _lastUsedWindowCollected = collectedSuccessfully;
    });
  }

  bool get _showUsedWindowSuccessSummary {
    if (!_hasUsedCurrentWindow) return false;
    if (_lastUsedWindowCollected != null) return _lastUsedWindowCollected!;
    return _caught;
  }

  bool get _showUsedWindowExhaustedSummary {
    if (!_hasUsedCurrentWindow) return false;
    if (_lastUsedWindowCollected != null) return !_lastUsedWindowCollected!;
    return _disappeared && !_caught;
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
        title: const Text('수집·도감'),
        actions: [
          TextButton.icon(
            onPressed: _openCatalog,
            style: TextButton.styleFrom(
              // AppBar 배경이 primary(청록)인데 전역 TextButton은 primary 색이라 글자가 안 보임
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(
              Icons.collections_bookmark_rounded,
              size: 22,
              color: Colors.white,
            ),
            label: const Text(
              '도감',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
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
                      '도감에 패키지 도안을 모아보세요.',
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
                      '도감 수집 1회 시도마다 금연코인 2개가\n소모됩니다.',
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
                                              '현재는 수집할 수 있는 시간이\n아닙니다.',
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
                                          ? _showUsedWindowSuccessSummary
                                              ? Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.check_circle_outline_rounded, size: 44, color: AppTheme.primary),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      '성공적으로 수집이 완료되었습니다.',
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
                                                      style: AppTheme.bodyMedium.copyWith(
                                                        color: AppTheme.textMuted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : _showUsedWindowExhaustedSummary
                                                  ? Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.sentiment_dissatisfied_rounded, size: 44, color: AppTheme.error),
                                                        const SizedBox(height: 10),
                                                        Text(
                                                          '이번 시간대 수집에 성공하지 못했어요.',
                                                          textAlign: TextAlign.center,
                                                          style: AppTheme.titleMedium.copyWith(
                                                            color: AppTheme.textPrimary,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 6),
                                                        Text(
                                                          '$_maxAttempts번의 시도를 모두 사용했습니다.\n다음 수집 시간(09:00, 12:00, 18:00, 22:00)에 다시 도전해 보세요.',
                                                          textAlign: TextAlign.center,
                                                          style: AppTheme.bodyMedium.copyWith(
                                                            color: AppTheme.textMuted,
                                                            fontSize: 11,
                                                            height: 1.35,
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.info_outline_rounded, size: 44, color: AppTheme.textMuted),
                                                        const SizedBox(height: 10),
                                                        Text(
                                                          '이번 시간대 수집이 종료되었습니다.',
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
                                                          style: AppTheme.bodyMedium.copyWith(
                                                            color: AppTheme.textMuted,
                                                            fontSize: 11,
                                                          ),
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
                                                        child: RemoteAssetImage(
                                                          assetKey: _currentAsset!,
                                                          fit: BoxFit.contain,
                                                          memCacheWidth: 480,
                                                          error: const Icon(
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
                                      child: Lottie.network(
                                        RemoteAssets.urlForKey('lottie/zippo.json').toString(),
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

