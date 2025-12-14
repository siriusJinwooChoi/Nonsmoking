import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class TreeScreen extends StatefulWidget {
  const TreeScreen({super.key});

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> with WidgetsBindingObserver {
  int water = 0;
  int growthStage = 1;
  int currentWater = 0;
  bool _isWatering = false;
  Timer? _waterTimer;

  final Map<int, int> stageGoal = {
    1: 500,
    2: 1500,
    3: 2000,
    4: 3000,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  Future<void> _initAll() async {
    await _loadData();
    await _handleReturnFromBackground();
    _startWaterTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waterTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveLastExitTime();
    } else if (state == AppLifecycleState.resumed) {
      _handleReturnFromBackground();
    }
  }

  Future<void> _saveLastExitTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastExitTime', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _handleReturnFromBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt('lastExitTime') ?? now;

    final elapsedMinutes = ((now - last) ~/ (1000 * 60)).clamp(0, 10000);
    if (elapsedMinutes > 0) {
      setState(() {
        currentWater = (currentWater + elapsedMinutes).clamp(0, 3000);
      });
      await prefs.setInt('currentWater', currentWater);
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      growthStage = prefs.getInt('growthStage') ?? 1;
      water = prefs.getInt('water') ?? 0;
      currentWater = prefs.getInt('currentWater') ?? 0;
    });
  }

  void _startWaterTimer() {
    _waterTimer?.cancel();
    _waterTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (currentWater < 3000) {
        setState(() => currentWater++);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('currentWater', currentWater);
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('growthStage', growthStage);
    await prefs.setInt('water', water);
    await prefs.setInt('currentWater', currentWater);
  }

  void _giveWater(int amount) async {
    if (_isWatering || growthStage > 5 || currentWater < amount) return;

    setState(() {
      _isWatering = true;
      currentWater -= amount;
      water += amount;
    });

    await Future.delayed(const Duration(seconds: 1));

    if (growthStage < 5 && water >= stageGoal[growthStage]!) {
      setState(() {
        growthStage++;
        water = 0;
      });
    }

    setState(() => _isWatering = false);
    _saveData();
  }

  void _showResetConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('나무 초기화'),
          content: const Text('정말로 나무를 1단계로 초기화하시겠습니까?'),
          actions: [
            TextButton(
              child: const Text('취소'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('초기화'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('growthStage', 1);
                await prefs.setInt('water', 0);
                await prefs.setInt('currentWater', 0);
                setState(() {
                  growthStage = 1;
                  water = 0;
                  currentWater = 0;
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('나무가 초기화되었습니다.')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final percent = growthStage < 5
        ? ((water / stageGoal[growthStage]!) * 100).clamp(0, 100).toStringAsFixed(0)
        : '100';

    return Scaffold(
      appBar: AppBar(
        title: const Text('나무 키우기'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              '나무는 최대 5단계까지 성장합니다! 꼭 성공하세요.',
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isWatering)
                    Positioned(
                      top: 0,
                      right: 150,
                      child: Lottie.asset(
                        'assets/lottie/water.json',
                        width: 130,
                        height: 130,
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    child: Image.asset(
                      'assets/tree_stage_$growthStage.png',
                      height: 160,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('현재 단계: $growthStage단계', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            Text('성장률: $percent%', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.water_drop, color: Colors.blue),
                SizedBox(width: 6),
                Text('보유한 물 (성장에 사용됨)'),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: growthStage < 5
                  ? (water / stageGoal[growthStage]!).clamp(0.0, 1.0)
                  : 1.0,
              minHeight: 12,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightBlue),
            ),
            const SizedBox(height: 10),
            Text('현재 물: ${currentWater}ml / 최대: 3000ml'),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (growthStage >= 5 || _isWatering || currentWater < 10)
                        ? null
                        : () => _giveWater(10),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: const Text('💧물 주기(10ml)', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (growthStage >= 5 || _isWatering || currentWater < 100)
                        ? null
                        : () => _giveWater(100),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: const Text('💧물 주기(100ml)', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed: _showResetConfirmationDialog,
              icon: const Icon(Icons.restart_alt),
              label: const Text('나무 초기화'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                textStyle: const TextStyle(fontSize: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}