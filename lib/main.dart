import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_manager.dart';
import 'ad_unit_ids.dart';
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
import 'screens/report_screen.dart';
import 'screens/attendance_screen.dart';
import 'data/main_tutorial_prefs.dart';
import 'widgets/main_screen_tutorial_overlay.dart';

// firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import 'analytics/app_analytics.dart';

import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';

import 'app_nav.dart';
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
    if (kDebugMode) {
      debugPrint(
        'Ad units(debug): banner=${AdUnitIds.banner}, interstitial=${AdUnitIds.interstitial}',
      );
    }
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
    // 수집/도감 진입 시 첫 렌더 지연을 줄이기 위해 담배갑 목록을 백그라운드로 워밍업
    unawaited(RemoteAssets.fetchCigarettePackKeysCached());
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

  bool _isOAuthCallbackUri(Uri uri) {
    if (uri.scheme != 'com.cjw.nonsmoking') return false;
    if (uri.host == 'login-callback') return true;
    final path = uri.path.toLowerCase();
    return path == '/login-callback' || path == '/login-callback/';
  }

  String? _extractOAuthCode(Uri uri) {
    final queryCode = uri.queryParameters['code'];
    if (queryCode != null && queryCode.isNotEmpty) return queryCode;
    if (uri.fragment.isNotEmpty) {
      try {
        final fromFragment = Uri.splitQueryString(uri.fragment)['code'];
        if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
      } catch (_) {}
    }
    return null;
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
      if (_isOAuthCallbackUri(uri)) {
        unawaited(() async {
          try {
            await BffOAuthService.completeWithAuthCode(_extractOAuthCode(uri));
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('OAuth deep link handling failed: $e\n$st');
            }
            await FirebaseCrashlytics.instance.recordError(
              e,
              st,
              reason: 'oauth_deep_link',
            );
          }
        }());
      }
    });
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null && _isOAuthCallbackUri(initial)) {
        try {
          await BffOAuthService.completeWithAuthCode(_extractOAuthCode(initial));
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('OAuth initial deep link handling failed: $e\n$st');
          }
          await FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason: 'oauth_initial_deep_link',
          );
        }
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
      navigatorKey: appRootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: '금연뱅크',
      theme: AppTheme.lightTheme,
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: const AppRootScreen(),
    );
  }
}

Future<bool> _checkIfConfigured() async {
  if (SupabaseConfig.isConfigured && BffAuthService.instance.isLoggedIn) {
    // 계정 전환 직후에는 로컬값(isConfigured)이 이전 계정 상태일 수 있어
    // 화면 분기 전에 한 번 동기화 상태를 강제 점검한다.
    await SupabaseSyncService.prepareLocalStateForCurrentUser();

    final prefs = await SharedPreferences.getInstance();
    final localConfigured = prefs.getBool('isConfigured') ?? false;
    if (!localConfigured) {
      // 로컬이 미완료면 서버 기준으로 한 번 더 pull 시도.
      await SupabaseSyncService.markPullRequiredOnNextLogin();
    }
    await SupabaseSyncService.runPostLoginPullIfNeeded();
  }

  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('isConfigured') ?? false;
}

Future<Map<String, int>> _loadUserSettings() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'dailyCigarettes': prefs.getInt('dailyCigarettes') ?? 0,
    'cigarettesPerPack': prefs.getInt('cigarettesPerPack') ?? 20,
    'pricePerPack': prefs.getInt('pricePerPack') ?? 4500,
  };
}

class AppRootScreen extends StatelessWidget {
  const AppRootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthGate(
      child: FutureBuilder<bool>(
        future: _checkIfConfigured(),
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
            future: _loadUserSettings(),
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

            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                // 루트(AuthGate)를 유지한 채 재진입해야 로그아웃/계정삭제 시
                // 로그인 화면으로 정확히 복귀하고, 재로그인 게이트도 일관된다.
                builder: (_) => const AppRootScreen(),
              ),
              (_) => false,
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

  final GlobalKey _tutorialStatsKey = GlobalKey(debugLabel: 'tutorial_stats');
  final GlobalKey _tutorialSmokedKey = GlobalKey(debugLabel: 'tutorial_smoked');
  final GlobalKey _tutorialReminderKey = GlobalKey(debugLabel: 'tutorial_reminder');
  final GlobalKey _tutorialNavGameKey = GlobalKey(debugLabel: 'tutorial_nav_game');
  final GlobalKey _tutorialNavGrowthKey = GlobalKey(debugLabel: 'tutorial_nav_growth');
  final GlobalKey _tutorialNavCollectKey = GlobalKey(debugLabel: 'tutorial_nav_collect');

  bool _showMainTutorial = false;
  final ScrollController _mainScrollController = ScrollController();

  // ✅ 전면광고
  InterstitialAd? _interstitialAd;
  Timer? _interstitialRetryTimer;

  // ✅ 클릭 카운트(20번마다 노출)
  int _clickCount = 0;
  static const int _showEvery = 20;

  @override
  void initState() {
    super.initState();
    _loadClickCount();
    _loadInterstitialAd();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_tryScheduleMainTutorial()));
  }

  @override
  void didUpdateWidget(MainScreenWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_tryScheduleMainTutorial()));
    }
  }

  /// 튜토리얼에서 초록 카드·버튼 위치가 맞도록, 오버레이를 띄우기 전에 항상 맨 위로 스크롤합니다.
  Future<void> _scrollMainToTop() async {
    if (!mounted) return;
    final c = _mainScrollController;
    for (var i = 0; i < 24 && !c.hasClients; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (!mounted) return;
    }
    if (!c.hasClients) return;
    await c.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> _tryScheduleMainTutorial() async {
    if (!mounted || currentIndex != 0) return;
    final done = await MainTutorialPrefs.isCompleted();
    if (!mounted || done) return;
    await _scrollMainToTop();
    if (!mounted) return;
    setState(() => _showMainTutorial = true);
  }

  Future<void> _completeMainTutorial() async {
    await MainTutorialPrefs.markCompleted();
    if (mounted) setState(() => _showMainTutorial = false);
  }

  Future<void> _replayMainTutorial() async {
    if (!mounted) return;
    if (currentIndex != 0) {
      setState(() => currentIndex = 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }
    await _scrollMainToTop();
    if (!mounted) return;
    setState(() => _showMainTutorial = true);
  }

  List<MainTutorialStep> _tutorialSteps() {
    return [
      MainTutorialStep(
        keys: [_tutorialStatsKey],
        highlightPadding: 12,
        cornerRadius: 20,
        title: '금연 현황을 한눈에',
        description:
            '이 초록 카드에서 금연 시작일·누적 일수와 목표,\n절약한 금액과 참은 담배 개비까지 바로 확인할 수 있어요.',
      ),
      MainTutorialStep(
        keys: [_tutorialSmokedKey],
        highlightPadding: 8,
        cornerRadius: 12,
        title: '흡연했을 때는 여기로',
        description:
            '흡연 후 「방금 피움(패턴 기록)」을 눌러 시간대·상황·감정을 남기면,\n기록을 바탕으로 나의 레포트가 만들어지고 패턴 알림도 준비돼요.',
      ),
      MainTutorialStep(
        keys: [_tutorialReminderKey],
        highlightPadding: 8,
        cornerRadius: 12,
        title: '알림은 여기에서',
        description:
            '「알림 설정」버튼에서 원하는 시간의 알림을 바로 추가할 수 있어요.\n흡연 기록이 쌓이면 피크 시간대를 분석해 패턴 알림도 자동으로 맞춰 드려요.',
      ),
      MainTutorialStep(
        keys: [_tutorialNavGameKey, _tutorialNavGrowthKey, _tutorialNavCollectKey],
        highlightPadding: 6,
        cornerRadius: 14,
        title: '금연을 재미있게 이어가요',
        description:
            '게임·성장시키기·수집·도감에서 미니게임·나무 키우기·도감 수집 등\n다양한 기능으로 금연을 계속 이어가 보세요.',
      ),
    ];
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
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialRetryTimer?.cancel();
          _interstitialRetryTimer = null;
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          if (kDebugMode) {
            debugPrint('Interstitial failed to load: $error');
          }
          // no fill/네트워크 오류 시 자동 재시도
          _scheduleInterstitialRetry();
        },
      ),
    );
  }

  void _scheduleInterstitialRetry() {
    if (_interstitialRetryTimer?.isActive ?? false) return;
    _interstitialRetryTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _interstitialAd != null) return;
      _loadInterstitialAd();
    });
  }

  void _showAdThenNavigate(int index) async {
    _clickCount++;
    await _saveClickCount();

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

  Future<void> _prepareTutorialStep(int stepIndex) async {
    if (!mounted || currentIndex != 0) return;
    final c = _mainScrollController;
    for (var i = 0; i < 8 && !c.hasClients; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
    }
    if (!c.hasClients) return;

    if (stepIndex == 1) {
      await c.animateTo(
        c.position.maxScrollExtent,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
      await Future<void>.delayed(const Duration(milliseconds: 160));
    } else if (stepIndex == 2) {
      final ctx = _tutorialReminderKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.32,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    } else if (stepIndex == 3) {
      await c.animateTo(
        c.position.maxScrollExtent,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  void dispose() {
    _interstitialRetryTimer?.cancel();
    _interstitialAd?.dispose();
    _mainScrollController.dispose();
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
        onShowTutorial: _replayMainTutorial,
        tutorialStatsCardKey: _tutorialStatsKey,
        tutorialSmokedButtonKey: _tutorialSmokedKey,
        tutorialReminderButtonKey: _tutorialReminderKey,
        mainScrollController: _mainScrollController,
      ),
      const GameMenuScreen(),
      const GrowthHubScreen(),
      const LungSmokingMenuScreen(),
      const ReportScreen(),
      const CigaretteCollectScreen(),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
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
                    _NavItem(key: _tutorialNavGameKey, icon: Icons.sports_esports_rounded, label: '게임', index: 1, current: currentIndex, onTap: _showAdThenNavigate),
                    _NavItem(key: _tutorialNavGrowthKey, icon: Icons.auto_awesome_rounded, label: '성장시키기', index: 2, current: currentIndex, onTap: _showAdThenNavigate),
                    _NavItem(icon: Icons.favorite_rounded, label: '건강/커뮤니티', index: 3, current: currentIndex, onTap: _showAdThenNavigate),
                    _NavItem(icon: Icons.insert_chart_rounded, label: '레포트', index: 4, current: currentIndex, onTap: _showAdThenNavigate),
                    _NavItem(key: _tutorialNavCollectKey, icon: Icons.inventory_2_rounded, label: '수집·도감', index: 5, current: currentIndex, onTap: _showAdThenNavigate),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showMainTutorial)
          Positioned.fill(
            child: MainScreenTutorialOverlay(
              steps: _tutorialSteps(),
              onFinished: () => unawaited(_completeMainTutorial()),
              onSkip: () => unawaited(_completeMainTutorial()),
              prepareStep: _prepareTutorialStep,
            ),
          ),
      ],
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
    super.key,
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