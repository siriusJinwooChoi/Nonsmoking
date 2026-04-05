import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_manager.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// ✅ WorkManager
import 'package:workmanager/workmanager.dart';
import 'notifications/daily_reminder_worker.dart';

// 온보딩 화면
import 'screens/intro/screen1_encourage.dart';
import 'screens/intro/screen2_goals.dart';
import 'screens/intro/screen3_reasons.dart';
import 'screens/intro/screen4_start_date.dart';
import 'screens/intro/screen5_duration.dart';
import 'screens/intro/screen6_daily_count.dart';
import 'screens/intro/screen7_per_pack.dart';
import 'screens/intro/screen8_price.dart';
import 'screens/intro/screen9_summary.dart';

// 주요 앱 화면
import 'screens/main_screen.dart';
import 'screens/game_menu_screen.dart';
import 'screens/growth_hub_screen.dart';
import 'screens/lung_smoking_menu_screen.dart';
import 'screens/cigarette_collect_screen.dart';
import 'screens/health_screen.dart';
import 'screens/attendance_screen.dart';

// firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'analytics/app_analytics.dart';

import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';

import 'auth/auth_gate.dart';
import 'auth/bff_auth_service.dart';
import 'auth/bff_oauth_service.dart';
import 'api/remote_assets.dart';
import 'supabase/supabase_config.dart';
import 'supabase/supabase_sync_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/fcm_daily_reminder_service.dart' show firebaseMessagingBackgroundHandler, FcmDailyReminderService;

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Android 15+ edge-to-edge와 맞춤 (상·하단 시스템 영역까지 그리기)
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // ✅ Firebase 먼저 초기화
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ✅ Crashlytics 설정은 Firebase 초기화 이후에!
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // ✅ 광고 초기화
    await MobileAds.instance.initialize();
    AdManager.loadAd();

    // ✅ WorkManager 초기화
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    if (SupabaseConfig.isConfigured) {
      await BffAuthService.instance.restoreSession();
    }
    await RemoteAssets.migrateLegacyCigarettePathsInPrefs();
    // 첫 프레임·스플래시를 막지 않도록 전체 push 는 백그라운드 (로그인·온보딩 완료 시에만 동작)
    unawaited(SupabaseSyncService.runStartupPushOnlyIfEligible());

    runApp(const QuitSmokingApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class QuitSmokingApp extends StatefulWidget {
  const QuitSmokingApp({super.key});

  @override
  State<QuitSmokingApp> createState() => _QuitSmokingAppState();
}

class _QuitSmokingAppState extends State<QuitSmokingApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _appLinkSub;

  Future<bool> checkIfConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isConfigured') ?? false;
  }

  Future<Map<String, int>> loadUserSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'dailyCigarettes': prefs.getInt('dailyCigarettes') ?? 0,
      'cigarettesPerPack': prefs.getInt('cigarettesPerPack') ?? 20,
      'pricePerPack': prefs.getInt('pricePerPack') ?? 4500,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initOAuthDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BffAuthService.instance.beforeSignOut = () async {
        await FcmDailyReminderService.instance.onBeforeSignOut();
      };
      unawaited(FcmDailyReminderService.instance.start());
    });
  }

  Future<void> _initOAuthDeepLinks() async {
    if (!SupabaseConfig.isConfigured) return;
    final appLinks = AppLinks();
    _appLinkSub = appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'com.cjw.nonsmoking' && uri.host == 'login-callback') {
        BffOAuthService.completeWithAuthCode(uri.queryParameters['code']);
      }
    });
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null &&
          initial.scheme == 'com.cjw.nonsmoking' &&
          initial.host == 'login-callback') {
        BffOAuthService.completeWithAuthCode(initial.queryParameters['code']);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _appLinkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshReminderSchedulesOnResume());
    }
  }

  Future<void> _refreshReminderSchedulesOnResume() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('isConfigured') ?? false)) return;
    await bootstrapCoreReminderSchedulesOnAppOpen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '금연뱅크',
      theme: AppTheme.lightTheme,
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: AuthGate(
        child: FutureBuilder<bool>(
          future: checkIfConfigured(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final isConfigured = snapshot.data!;
            if (!isConfigured) {
              return const IntroFlowWrapper();
            }

            return FutureBuilder<Map<String, int>>(
              future: loadUserSettings(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final settings = userSnapshot.data!;
                return AttendanceGate(
                  dailyCigarettes: settings['dailyCigarettes']!,
                  cigarettesPerPack: settings['cigarettesPerPack']!,
                  pricePerPack: settings['pricePerPack']!,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class IntroFlowWrapper extends StatefulWidget {
  const IntroFlowWrapper({super.key});

  @override
  State<IntroFlowWrapper> createState() => _IntroFlowWrapperState();
}

class _IntroFlowWrapperState extends State<IntroFlowWrapper> {
  int currentIndex = 0;
  int dailyCigarettes = 0;
  int cigarettesPerPack = 0;
  int pricePerPack = 0;
  int durationDays = 90;
  /// 금연 이유 화면(3단계)에서 선택·입력한 문구
  String _onboardingQuitReason = '';

  void nextScreen() => setState(() => currentIndex++);

  static const int _introTotalSteps = 9;

  Widget _startFlow() {
    final step = currentIndex + 1;
    switch (currentIndex) {
      case 0:
        return Screen1Encourage(onNext: nextScreen, step: step, totalSteps: _introTotalSteps);

      case 1:
        return Screen2Goals(onNext: nextScreen, step: step, totalSteps: _introTotalSteps);

      case 2:
        return Screen3Reasons(
          onContinueWithReason: (reason) {
            setState(() => _onboardingQuitReason = reason);
            nextScreen();
          },
          step: step,
          totalSteps: _introTotalSteps,
        );

      case 3:
        return Screen4StartDate(onNext: nextScreen, step: step, totalSteps: _introTotalSteps);

      case 4:
        return Screen5Duration(onNext: (days) {
          setState(() => durationDays = days);
          nextScreen();
        }, step: step, totalSteps: _introTotalSteps);

      case 5:
        return Screen6DailyCount(onNext: (value) {
          setState(() => dailyCigarettes = value);
          nextScreen();
        }, step: step, totalSteps: _introTotalSteps);

      case 6:
        return Screen7PerPack(onNext: (value) {
          setState(() => cigarettesPerPack = value);
          nextScreen();
        }, step: step, totalSteps: _introTotalSteps);

      case 7:
        return Screen8Price(onNext: (value) {
          setState(() => pricePerPack = value);
          nextScreen();
        }, step: step, totalSteps: _introTotalSteps);

      case 8:
        return Screen9Summary(
          step: step,
          totalSteps: _introTotalSteps,
          onNext: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isConfigured', true);

            await AppAnalytics.log('onboarding_complete', params: {
              'daily_cigs': dailyCigarettes,
              'cigs_per_pack': cigarettesPerPack,
              'price_per_pack': pricePerPack,
              'duration_days': durationDays,
            });

            await prefs.setInt('dailyCigarettes', dailyCigarettes);
            await prefs.setInt('cigarettesPerPack', cigarettesPerPack);
            await prefs.setInt('pricePerPack', pricePerPack);
            await prefs.setInt('duration_days', durationDays);

            final reason = _onboardingQuitReason.trim();
            if (reason.isNotEmpty) {
              final now = DateTime.now().millisecondsSinceEpoch;
              final id = 'onboard_$now';
              await prefs.setString('pinnedReasonText', reason);
              await prefs.setString(
                'quitReasons_v1',
                jsonEncode([
                  {
                    'id': id,
                    'text': reason,
                    'pinned': true,
                    'createdAt': now,
                    'displayNumber': 1,
                  },
                ]),
              );
              await prefs.setString('selectedReasonId', id);
              await prefs.setString(kSelectedReasonTextKey, reason);
              await prefs.setBool(kReasonNotificationEnabledKey, true);
            }

            unawaited(SupabaseSyncService.pushLocalToRemoteIfEligible());

            if (!mounted) return;

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => MainScreenWrapper(
                  dailyCigarettes: dailyCigarettes,
                  cigarettesPerPack: cigarettesPerPack,
                  pricePerPack: pricePerPack,
                ),
              ),
            );
          },
          dailyCigarettes: dailyCigarettes,
          cigarettesPerPack: cigarettesPerPack,
          pricePerPack: pricePerPack,
          durationDays: durationDays,
        );

      default:
        return const Scaffold(
          body: Center(child: Text('잘못된 화면 흐름입니다.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => _startFlow();
}

/// 앱 실행 시 출석 화면을 먼저 띄우고, 닫으면 메인으로.
class AttendanceGate extends StatefulWidget {
  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;

  const AttendanceGate({
    super.key,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
  });

  @override
  State<AttendanceGate> createState() => _AttendanceGateState();
}

class _AttendanceGateState extends State<AttendanceGate> {
  bool _showAttendance = true;
  int _refreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applySkipOverlayFlag());
      // 알림 예약은 MainScreen 첫 프레임에서 bootstrapCoreReminderSchedulesOnAppOpen 한 번만 수행
    });
  }

  Future<void> _applySkipOverlayFlag() async {
    final skip = await shouldSkipAttendanceOverlayToday();
    if (!mounted) return;
    if (skip) setState(() => _showAttendance = false);
  }

  void _onAttendanceClose() {
    setState(() {
      _showAttendance = false;
      _refreshTrigger++;
    });
  }

  void _onMainTabSelected() {
    setState(() => _refreshTrigger++);
  }

  @override
  Widget build(BuildContext context) {
    final mainScreen = MainScreenWrapper(
      dailyCigarettes: widget.dailyCigarettes,
      cigarettesPerPack: widget.cigarettesPerPack,
      pricePerPack: widget.pricePerPack,
      refreshTrigger: _refreshTrigger,
      onMainTabSelected: _onMainTabSelected,
    );
    if (!_showAttendance) return mainScreen;
    return Stack(
      children: [
        mainScreen,
        Positioned.fill(
          child: AttendanceScreen(
            onClose: _onAttendanceClose,
            onAttendanceRecorded: SupabaseSyncService.pushLocalToRemoteIfEligible,
          ),
        ),
      ],
    );
  }
}

class MainScreenWrapper extends StatefulWidget {
  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;
  final int refreshTrigger;
  final VoidCallback? onMainTabSelected;

  const MainScreenWrapper({
    super.key,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
    this.refreshTrigger = 0,
    this.onMainTabSelected,
  });

  @override
  State<MainScreenWrapper> createState() => _MainScreenWrapperState();
}

class _MainScreenWrapperState extends State<MainScreenWrapper> {
  int currentIndex = 0;

  // ✅ 전면광고
  InterstitialAd? _interstitialAd;

  // ✅ 클릭 카운트(20번마다 노출)
  int _clickCount = 0;
  static const int _showEvery = 20;

  @override
  void initState() {
    super.initState();
    _loadClickCount();
    _loadInterstitialAd();
  }

  Future<void> _loadClickCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _clickCount = prefs.getInt('clickCount') ?? 0;
    });
  }

  Future<void> _saveClickCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('clickCount', _clickCount);
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      // ✅ 실제 광고 ID
      adUnitId: 'ca-app-pub-2294312189421130/4538637779',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          if (kDebugMode) {
            debugPrint('Interstitial failed to load: $error');
          }
        },
      ),
    );
  }

  void _showAdThenNavigate(int index) async {
    _clickCount++;
    await _saveClickCount();

    if (kDebugMode) {
      debugPrint('menu click=$_clickCount, adLoaded=${_interstitialAd != null}');
    }

    // ✅ 20번마다 광고
    if (_clickCount % _showEvery == 0 && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
          setState(() => currentIndex = index);
          if (index == 0) widget.onMainTabSelected?.call();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
          setState(() => currentIndex = index);
          if (index == 0) widget.onMainTabSelected?.call();
        },
      );

      _interstitialAd!.show();
    } else {
      setState(() => currentIndex = index);
      if (index == 0) widget.onMainTabSelected?.call();
      // 다음을 위해 계속 로드
      if (_interstitialAd == null) _loadInterstitialAd();
    }
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MainScreen(
        onAlarmTap: () => _showAdThenNavigate(0),
        onCravingTap: () => _showAdThenNavigate(1),
        onResetTap: () => _showAdThenNavigate(0),
        onReasonTap: () => _showAdThenNavigate(0),
        onHelperTap: () => _showAdThenNavigate(0),
        refreshTrigger: widget.refreshTrigger,
        dailyCigarettes: widget.dailyCigarettes,
        cigarettesPerPack: widget.cigarettesPerPack,
        pricePerPack: widget.pricePerPack,
      ),
      const GameMenuScreen(),
      const GrowthHubScreen(),
      const LungSmokingMenuScreen(),
      const CigaretteCollectScreen(),
      const HealthScreen(),
    ];

    return Scaffold(
      body: screens[currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: '메인', index: 0, current: currentIndex, onTap: _showAdThenNavigate),
                _NavItem(icon: Icons.sports_esports_rounded, label: '게임', index: 1, current: currentIndex, onTap: _showAdThenNavigate),
                _NavItem(icon: Icons.auto_awesome_rounded, label: '성장시키기', index: 2, current: currentIndex, onTap: _showAdThenNavigate),
                _NavItem(icon: Icons.favorite_rounded, label: '폐·건강', index: 3, current: currentIndex, onTap: _showAdThenNavigate),
                _NavItem(icon: Icons.inventory_2_rounded, label: '수집·도감', index: 4, current: currentIndex, onTap: _showAdThenNavigate),
                _NavItem(icon: Icons.favorite_border_rounded, label: '건강', index: 5, current: currentIndex, onTap: _showAdThenNavigate),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = current == index;
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}