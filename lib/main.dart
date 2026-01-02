import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:timezone/data/latest_all.dart' as tzData;
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
import 'screens/game_screen.dart';
import 'screens/tree_screen.dart';
import 'screens/lung_screen.dart';
import 'screens/health_screen.dart';
import 'screens/smoking_screen.dart';

// firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';
import '../analytics/app_analytics.dart';

import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Firebase 먼저 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Crashlytics 설정은 Firebase 초기화 이후에!
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  runZonedGuarded(() async {
    // ✅ 광고 초기화
    await MobileAds.instance.initialize();

    // ✅ WorkManager 초기화
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    tzData.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    runApp(const QuitSmokingApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class QuitSmokingApp extends StatelessWidget {
  const QuitSmokingApp({super.key});

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
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: checkIfConfigured(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        final isConfigured = snapshot.data!;
        if (!isConfigured) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: IntroFlowWrapper(),
          );
        }

        return FutureBuilder<Map<String, int>>(
          future: loadUserSettings(),
          builder: (context, userSnapshot) {
            if (!userSnapshot.hasData) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: CircularProgressIndicator())),
              );
            }

            final settings = userSnapshot.data!;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: '금연 앱',
              theme: ThemeData(primarySwatch: Colors.teal),
              home: MainScreenWrapper(
                dailyCigarettes: settings['dailyCigarettes']!,
                cigarettesPerPack: settings['cigarettesPerPack']!,
                pricePerPack: settings['pricePerPack']!,
              ),
              navigatorObservers: [
                FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
              ],
            );
          },
        );
      },
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

  void nextScreen() => setState(() => currentIndex++);

  Widget _startFlow() {
    switch (currentIndex) {
      case 0:
        return Screen1Encourage(onNext: nextScreen);

      case 1:
        return Screen2Goals(onNext: nextScreen);

      case 2:
        return Screen3Reasons(onNext: nextScreen);

      case 3:
        return Screen4StartDate(onNext: nextScreen);

      case 4:
        return Screen5Duration(onNext: (days) {
          setState(() => durationDays = days);
          nextScreen();
        });

      case 5:
        return Screen6DailyCount(onNext: (value) {
          setState(() => dailyCigarettes = value);
          nextScreen();
        });

      case 6:
        return Screen7PerPack(onNext: (value) {
          setState(() => cigarettesPerPack = value);
          nextScreen();
        });

      case 7:
        return Screen8Price(onNext: (value) {
          setState(() => pricePerPack = value);
          nextScreen();
        });

      case 8:
        return Screen9Summary(
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

class MainScreenWrapper extends StatefulWidget {
  final int dailyCigarettes;
  final int cigarettesPerPack;
  final int pricePerPack;

  const MainScreenWrapper({
    super.key,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
  });

  @override
  State<MainScreenWrapper> createState() => _MainScreenWrapperState();
}

class _MainScreenWrapperState extends State<MainScreenWrapper> {
  int currentIndex = 0;

  // ✅ 전면광고
  InterstitialAd? _interstitialAd;

  // ✅ 클릭 카운트(10번마다 노출)
  int _clickCount = 0;
  static const int _showEvery = 10;

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
          debugPrint("Interstitial failed to load: $error");
        },
      ),
    );
  }

  void _showAdThenNavigate(int index) async {
    _clickCount++;
    await _saveClickCount();

    // ✅ 디버그 확인용(원하면 삭제)
    debugPrint("menu click=$_clickCount, adLoaded=${_interstitialAd != null}");

    // ✅ 10번마다 광고
    if (_clickCount % _showEvery == 0 && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
          setState(() => currentIndex = index);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
          setState(() => currentIndex = index);
        },
      );

      _interstitialAd!.show();
    } else {
      setState(() => currentIndex = index);
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
        dailyCigarettes: widget.dailyCigarettes,
        cigarettesPerPack: widget.cigarettesPerPack,
        pricePerPack: widget.pricePerPack,
      ),
      const GameScreen(),
      const TreeScreen(),
      const LungScreen(),
      const SmokingScreen(),
      const HealthScreen(),
    ];

    return Scaffold(
      body: screens[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        onTap: (index) => _showAdThenNavigate(index), // ✅ 여기만 변경!
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '메인'),
          BottomNavigationBarItem(icon: Icon(Icons.videogame_asset), label: '게임'),
          BottomNavigationBarItem(icon: Icon(Icons.nature), label: '나무 키우기'),
          BottomNavigationBarItem(icon: Icon(Icons.healing), label: '나의 폐'),
          BottomNavigationBarItem(icon: Icon(Icons.smoking_rooms), label: '흡연하기'),
          BottomNavigationBarItem(icon: Icon(Icons.health_and_safety), label: '건강'),
        ],
      ),
    );
  }
}