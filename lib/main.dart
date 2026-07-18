import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'screens/intro/intro_a_welcome.dart';
import 'screens/intro/intro_b_habits.dart';
import 'screens/intro/intro_c_start.dart';
import 'screens/intro/intro_d_quit_mode.dart';
import 'screens/intro/intro_e_summary.dart';
import 'data/quit_mode_prefs.dart';

// 주요 앱 화면
import 'screens/main_screen.dart';
import 'screens/quit_room/quit_room_list_screen.dart';
import 'screens/more_hub_screen.dart';
// attendance screen removed
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
import 'notifications/pattern_slots_remote_sync.dart';
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
    PatternSlotsRemoteSync.onSlotsChanged =
        SupabaseSyncService.pushLocalToRemoteIfEligible;
    await RemoteAssets.migrateLegacyCigarettePathsInPrefs();
    // 수집/도감 진입 시 첫 렌더 지연을 줄이기 위해 담배갑 목록을 백그라운드로 워밍업
    unawaited(RemoteAssets.fetchCigarettePackKeysCached());
    // 첫 프레임·스플래시를 막지 않도록 전체 push 는 백그라운드 (로그인·온보딩 완료 시에만 동작)
    unawaited(SupabaseSyncService.runStartupPushOnlyIfEligible());

    appRootScreenBuilder = () => const AppRootScreen();
    runApp(const QuitSmokingApp());
  }, (error, stack) {
    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } else if (kDebugMode) {
        debugPrint('Unhandled startup error: $error\n$stack');
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('Unhandled startup error: $error\n$stack');
      }
    }
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
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
      ],
      theme: AppTheme.lightTheme,
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: ValueListenableBuilder<int>(
        valueListenable: appRootGeneration,
        builder: (_, gen, __) {
          return KeyedSubtree(
            key: ValueKey('app_home_$gen'),
            child: const AppRootScreen(),
          );
        },
      ),
    );
  }
}

Future<bool> _checkIfConfigured() async {
  final needsIntro = await SupabaseSyncService.shouldShowIntroFlow();
  return !needsIntro;
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
        key: ValueKey('configured_${appRootGeneration.value}'),
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
              return MainScreenWrapper(
                dailyCigarettes: settings['dailyCigarettes']!,
                cigarettesPerPack: settings['cigarettesPerPack']!,
                pricePerPack: settings['pricePerPack']!,
                refreshTrigger: 0,
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
  int _step = 0;

  // 각 단계에서 수집한 데이터
  String _quitReason = '';
  int _dailyCigarettes = 10;
  int _cigarettesPerPack = 20;
  int _pricePerPack = 4500;
  int _durationDays = 365;
  DateTime? _startTime;
  QuitMode _quitMode = QuitMode.continuous;

  void _next() => setState(() => _step++);
  void _back() => setState(() { if (_step > 0) _step--; });

  Future<void> _finish(DateTime startTime) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('startTime', startTime.millisecondsSinceEpoch);
    await prefs.setInt(QuitModePrefs.originStartTimeKey, startTime.millisecondsSinceEpoch);
    await QuitModePrefs.setMode(_quitMode, prefs: prefs);
    await prefs.setInt('dailyCigarettes', _dailyCigarettes);
    await prefs.setInt('cigarettesPerPack', _cigarettesPerPack);
    await prefs.setInt('pricePerPack', _pricePerPack);
    await prefs.setInt('duration_days', _durationDays);
    await prefs.setBool('isConfigured', true);
    await SupabaseSyncService.clearForceOnboardingFlag();

    await AppAnalytics.log('onboarding_complete', params: {
      'daily_cigs': _dailyCigarettes,
      'cigs_per_pack': _cigarettesPerPack,
      'price_per_pack': _pricePerPack,
      'duration_days': _durationDays,
      'quit_mode': _quitMode.storageValue,
    });

    final reason = _quitReason.trim();
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

    // 서버에 완료 상태를 먼저 반영한 뒤 루트로 이동해 intro 재진입을 막는다.
    try {
      await SupabaseSyncService.pushLocalToRemoteIfEligible();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const AppRootScreen(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case 0:
        return IntroAWelcome(
          initialReason:
              _quitReason.trim().isEmpty ? null : _quitReason.trim(),
          onNext: (reason) {
            setState(() => _quitReason = reason);
            _next();
          },
        );

      case 1:
        return IntroBHabits(
          initialDailyCigarettes: _dailyCigarettes,
          initialPricePerPack: _pricePerPack,
          initialCigarettesPerPack: _cigarettesPerPack,
          initialDurationDays: _durationDays,
          onBack: _back,
          onNext: ({
            required int dailyCigarettes,
            required int pricePerPack,
            required int cigarettesPerPack,
            required int durationDays,
          }) {
            setState(() {
              _dailyCigarettes = dailyCigarettes;
              _pricePerPack = pricePerPack;
              _cigarettesPerPack = cigarettesPerPack;
              _durationDays = durationDays;
            });
            _next();
          },
        );

      case 2:
        return IntroESummary(
          dailyCigarettes: _dailyCigarettes,
          cigarettesPerPack: _cigarettesPerPack,
          pricePerPack: _pricePerPack,
          durationDays: _durationDays,
          onBack: _back,
          onNext: _next,
        );

      case 3:
        return IntroDQuitMode(
          initialMode: _quitMode,
          onBack: _back,
          onNext: (mode) {
            setState(() => _quitMode = mode);
            _next();
          },
        );

      case 4:
        return IntroCStart(
          initialStartTime: _startTime,
          quitMode: _quitMode,
          onChangeQuitMode: _back,
          onStartTimeDraft: (t) => _startTime = t,
          onBack: _back,
          onNext: (startTime) {
            setState(() => _startTime = startTime);
            _finish(startTime);
          },
        );

      default:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
    }
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
  final GlobalKey _tutorialSosKey = GlobalKey(debugLabel: 'tutorial_sos');
  final GlobalKey _tutorialSmokedKey = GlobalKey(debugLabel: 'tutorial_smoked');
  final GlobalKey _tutorialReminderKey = GlobalKey(debugLabel: 'tutorial_reminder');
  final GlobalKey _tutorialNavRoomKey = GlobalKey(debugLabel: 'tutorial_nav_room');

  bool _showMainTutorial = false;
  final ScrollController _mainScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
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
            '누적 일수·절약 금액·참은 개비를\n한 카드에서 확인해요.\n목표일을 탭하면 7일·30일 등\n목표를 바꿀 수 있어요.',
      ),
      MainTutorialStep(
        keys: [_tutorialSosKey],
        highlightPadding: 8,
        cornerRadius: 16,
        title: '욕구가 올 때 못참겠어요',
        description:
            '흡연 욕구가 강할 때 눌러보세요.\n3분 타이머와 미션, 게임으로\n마음을 돌릴 수 있어요.',
      ),
      MainTutorialStep(
        keys: [_tutorialSmokedKey],
        highlightPadding: 8,
        cornerRadius: 12,
        title: '기록은 두 가지',
        description:
            '흡연 후 「흡연 기록」으로\n시간·상황·감정을 남기고,\n욕구가 올 때는 「욕구 기록」으로\n패턴을 쌓아 보세요.',
      ),
      MainTutorialStep(
        keys: [_tutorialReminderKey],
        highlightPadding: 8,
        cornerRadius: 12,
        title: '알림은 여기에서',
        description:
            '「알림 설정」에서 원하는 시간을\n추가할 수 있어요.\n기록이 쌓이면 피크 시간대를 분석해\n패턴 알림도 맞춰 드려요.',
      ),
      MainTutorialStep(
        keys: [_tutorialNavRoomKey],
        highlightPadding: 6,
        cornerRadius: 14,
        title: '금연방으로 함께 버텨요',
        description:
            '하단 「금연방」 탭에서\n혼자 또는 파트너와 함께\n금연 사진·글을 올리고\n서로 응원받을 수 있어요.',
      ),
    ];
  }

  void _onTabSelected(int index) {
    setState(() => currentIndex = index);
    if (index == 0) widget.onMainTabSelected?.call();
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
      final ctx = _tutorialSosKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    } else if (stepIndex == 2) {
      await c.animateTo(
        c.position.maxScrollExtent,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
      await Future<void>.delayed(const Duration(milliseconds: 160));
    } else if (stepIndex == 3) {
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
    }
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MainScreen(
        refreshTrigger: widget.refreshTrigger,
        dailyCigarettes: widget.dailyCigarettes,
        cigarettesPerPack: widget.cigarettesPerPack,
        pricePerPack: widget.pricePerPack,
        onShowTutorial: _replayMainTutorial,
        tutorialStatsCardKey: _tutorialStatsKey,
        tutorialSosButtonKey: _tutorialSosKey,
        tutorialSmokedButtonKey: _tutorialSmokedKey,
        tutorialReminderButtonKey: _tutorialReminderKey,
        mainScrollController: _mainScrollController,
      ),
      const QuitRoomListScreen(),
      const MoreHubScreen(),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
          body: screens[currentIndex],
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: AppTheme.surfaceCard,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  children: [
                    _NavItem(icon: Icons.home_rounded, label: '홈', index: 0, current: currentIndex, onTap: _onTabSelected),
                    _NavItem(key: _tutorialNavRoomKey, icon: Icons.people_rounded, label: '금연방', index: 1, current: currentIndex, onTap: _onTabSelected),
                    _NavItem(icon: Icons.grid_view_rounded, label: '더보기', index: 2, current: currentIndex, onTap: _onTabSelected),
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
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primarySurface : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTheme.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}