import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Analytics helper
import '../analytics/app_analytics.dart';

class TreeScreen extends StatefulWidget {
  const TreeScreen({super.key});

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int water = 0;         // 누적 물(성장용)
  int growthStage = 1;   // 성장 단계
  int currentWater = 0;  // 보유 물(ml)

  bool _isWatering = false;
  Timer? _waterTimer;

  late AnimationController _shakeController;

  // ✅ 설정: 2분에 1ml
  static const int _waterIntervalMinutes = 2;
  static const int _maxCurrentWater = 3000;

  // ✅ SharedPreferences keys
  static const String _kGrowthStage = 'growthStage';
  static const String _kWater = 'water';
  static const String _kCurrentWater = 'currentWater';
  static const String _kLastWaterUpdateTime = 'lastWaterUpdateTime'; // ✅ 새 키

  final Map<int, int> stageGoal = {
    1: 1000,
    2: 2500,
    3: 4000,
    4: 5000,
  };

  @override
  void initState() {
    super.initState();
    AppAnalytics.screen('tree_screen');
    WidgetsBinding.instance.addObserver(this);

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _initAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waterTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _initAll() async {
    await _loadData();
    await _applyWaterRegenFromLastUpdate(); // ✅ 복귀/재진입 시 경과분 반영
    _startWaterTimer();                    // ✅ 2분 주기 타이머
  }

  /// ✅ 앱이 백그라운드/포그라운드 이동할 때도 동일 로직 적용
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistLastWaterUpdateTime(); // ✅ 마지막 갱신 시각 저장
    } else if (state == AppLifecycleState.resumed) {
      _applyWaterRegenFromLastUpdate(); // ✅ 돌아오면 경과분 반영
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      growthStage = prefs.getInt(_kGrowthStage) ?? 1;
      water = prefs.getInt(_kWater) ?? 0;
      currentWater = prefs.getInt(_kCurrentWater) ?? 0;
    });

    // ✅ 최초 실행 시 lastWaterUpdateTime이 없으면 지금으로 세팅
    final hasLast = prefs.getInt(_kLastWaterUpdateTime) != null;
    if (!hasLast) {
      await prefs.setInt(_kLastWaterUpdateTime, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGrowthStage, growthStage);
    await prefs.setInt(_kWater, water);
    await prefs.setInt(_kCurrentWater, currentWater);
  }

  Future<void> _persistLastWaterUpdateTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastWaterUpdateTime, DateTime.now().millisecondsSinceEpoch);
  }

  /// ✅ 핵심: 마지막 업데이트 시각 기준으로 "2분당 1ml"만 증가
  Future<void> _applyWaterRegenFromLastUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastMs = prefs.getInt(_kLastWaterUpdateTime) ?? nowMs;

    final elapsedMinutes = ((nowMs - lastMs) ~/ (1000 * 60)).clamp(0, 100000);

    // 2분당 1ml -> 증가량 = 경과분 / 2
    final add = (elapsedMinutes ~/ _waterIntervalMinutes);

    if (add > 0 && mounted) {
      setState(() {
        currentWater = (currentWater + add).clamp(0, _maxCurrentWater);
      });
      await prefs.setInt(_kCurrentWater, currentWater);
    }

    // ✅ 여기서 now로 갱신해줘야 다음에 "또 같은 분을 중복 반영"하지 않음
    await prefs.setInt(_kLastWaterUpdateTime, nowMs);
  }

  void _startWaterTimer() {
    _waterTimer?.cancel();

    _waterTimer = Timer.periodic(
      const Duration(minutes: _waterIntervalMinutes),
          (_) async {
        if (!mounted) return;

        if (currentWater < _maxCurrentWater) {
          setState(() => currentWater++);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(_kCurrentWater, currentWater);
          await prefs.setInt(
            _kLastWaterUpdateTime,
            DateTime.now().millisecondsSinceEpoch,
          );
        } else {
          // 꽉 차면 굳이 계속 돌 필요 없음(선택)
          // _waterTimer?.cancel();
        }
      },
    );
  }

  void _giveWater(int amount) async {
    if (_isWatering || growthStage > 5 || currentWater < amount) return;

    final stageBefore = growthStage;
    final currentBefore = currentWater;

    setState(() {
      _isWatering = true;
      currentWater -= amount;
      water += amount;
    });

    _shakeController.forward(from: 0);

    await Future.delayed(const Duration(seconds: 1));

    if (growthStage < 5 && water >= stageGoal[growthStage]!) {
      setState(() {
        growthStage++;
        water = 0;
      });
    }

    setState(() => _isWatering = false);
    await _saveData();

    // ✅ Analytics
    unawaited(AppAnalytics.log('tree_water', params: {
      'amount': amount,
      'stage_before': stageBefore,
      'stage_after': growthStage,
      'current_water_before': currentBefore,
      'current_water_after': currentWater,
      'source': 'tree_screen',
    }));
  }

  void _showResetConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('🌱 나무 초기화'),
          content: const Text('정말로 나무를 초기화하시겠습니까?'),
          actions: [
            TextButton(
              child: const Text('취소'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('초기화'),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt(_kGrowthStage, 1);
                await prefs.setInt(_kWater, 0);
                await prefs.setInt(_kCurrentWater, 0);
                await prefs.setInt(
                  _kLastWaterUpdateTime,
                  DateTime.now().millisecondsSinceEpoch,
                );

                setState(() {
                  growthStage = 1;
                  water = 0;
                  currentWater = 0;
                });

                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🌳 나무가 초기화되었습니다.')),
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
        ? ((water / stageGoal[growthStage]!) * 100)
        .clamp(0, 100)
        .toStringAsFixed(0)
        : '100';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9F4),
      appBar: AppBar(
        title: const Text('나의 성장 나무 🌳',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.green.shade700,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4)
                  ],
                ),
                padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: const Column(
                  children: [
                    Text(
                      '꾸준히 물을 주면 나무가 자라요 🌱',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '현재 나무는 5단계까지 성장합니다.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (_isWatering)
                      Positioned(
                        top: -20,
                        right: 80,
                        child: Lottie.asset(
                          'assets/lottie/water.json',
                          width: 120,
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                      ),
                    AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        final angle =
                            sin(_shakeController.value * 2 * pi) * 0.05;
                        return Transform.rotate(
                          angle: angle,
                          child: Image.asset(
                            'assets/tree_stage_$growthStage.png',
                            height: 160,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text('🌿 현재 단계: $growthStage단계',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('📈 성장률: $percent%',
                      style:
                      const TextStyle(fontSize: 15, color: Colors.teal)),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 3)
                  ],
                ),
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.water_drop,
                            color: Colors.lightBlue, size: 18),
                        SizedBox(width: 6),
                        Text('보유한 물 (ml)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: growthStage < 5
                          ? (water / stageGoal[growthStage]!).clamp(0.0, 1.0)
                          : 1.0,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.lightBlueAccent),
                    ),
                    const SizedBox(height: 6),
                    Text('현재 물: $currentWater ml / 최대: $_maxCurrentWater ml',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    const Text('※ 물은 2분마다 1ml씩 증가합니다.',
                        style:
                        TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                      (growthStage >= 5 || _isWatering || currentWater < 10)
                          ? null
                          : () => _giveWater(10),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.lightBlue.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('💧 10ml',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                      (growthStage >= 5 || _isWatering || currentWater < 100)
                          ? null
                          : () => _giveWater(100),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('💦 100ml',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showResetConfirmationDialog,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('나무 초기화'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}