// Flutter의 핵심 UI 패키지
import 'package:flutter/material.dart';
// 사용자 설정을 앱에 저장하기 위한 패키지
import 'package:shared_preferences/shared_preferences.dart';

// 온보딩(초기 설정) 화면 관련 import
import 'screens/intro/screen1_encourage.dart';
import 'screens/intro/screen2_goals.dart';
import 'screens/intro/screen3_reasons.dart';
import 'screens/intro/screen4_start_date.dart';
import 'screens/intro/screen5_duration.dart';
import 'screens/intro/screen6_daily_count.dart';
import 'screens/intro/screen7_per_pack.dart';
import 'screens/intro/screen8_price.dart';
import 'screens/intro/screen9_summary.dart';

// 실제 앱 사용 중 표시되는 주요 화면 import
import 'screens/main_screen.dart';
import 'screens/game_screen.dart';
import 'screens/tree_screen.dart';
import 'screens/lung_screen.dart';
import 'screens/youtube_screen.dart';
import 'screens/health_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuitSmokingApp());
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
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        final isConfigured = snapshot.data!;
        if (!isConfigured) {
          return const MaterialApp(home: IntroFlowWrapper());
        } else {
          return FutureBuilder<Map<String, int>>(
            future: loadUserSettings(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData) {
                return const MaterialApp(
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
              );
            },
          );
        }
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
            await prefs.setInt('dailyCigarettes', dailyCigarettes);
            await prefs.setInt('cigarettesPerPack', cigarettesPerPack);
            await prefs.setInt('pricePerPack', pricePerPack);

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
  final Duration quitDuration = const Duration(days: 5, hours: 10);

  @override
  Widget build(BuildContext context) {
    final screens = [
      MainScreen(
        onAlarmTap: () => setState(() => currentIndex = 5),
        onCravingTap: () => setState(() => currentIndex = 1),
        onResetTap: () => setState(() => currentIndex = 0),
        dailyCigarettes: widget.dailyCigarettes,
        cigarettesPerPack: widget.cigarettesPerPack,
        pricePerPack: widget.pricePerPack,
      ),
      const GameScreen(),
      const TreeScreen(),
      const LungScreen(),
      const YoutubeScreen(),
      HealthScreen(quitDuration: quitDuration),
    ];

    return Scaffold(
      body: screens[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        onTap: (index) => setState(() => currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '메인'),
          BottomNavigationBarItem(icon: Icon(Icons.videogame_asset), label: '게임'),
          BottomNavigationBarItem(icon: Icon(Icons.nature), label: '나무'),
          BottomNavigationBarItem(icon: Icon(Icons.healing), label: '나의 폐'),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: '유튜브'),
          BottomNavigationBarItem(icon: Icon(Icons.health_and_safety), label: '건강'),
        ],
      ),
    );
  }
}