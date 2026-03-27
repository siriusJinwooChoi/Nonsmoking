import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../notifications/daily_reminder_worker.dart';
import '../supabase/supabase_config.dart';
import '../api/attendance_api_service.dart';
/// 출석체크 1~28일, 7x4 그리드. 금연코인 10/20(7,14,21,28일).
const String kAttendanceStreakDayKey = 'attendance_streak_day';
const String kAttendanceLastDateKey = 'attendance_last_date';
const String kGoldenCoinsKey = 'golden_coins';
/// 이 날짜(yyyy-MM-dd)에 "오늘 하루 출석 화면 안 보기"를 선택한 경우, 당일 재실행 시 출석 오버레이 생략
const String kAttendanceSkipOverlayDateKey = 'attendance_skip_overlay_date';
const int kAttendanceDays = 28;
const int kCoinsPerDay = 15;
const int kCoinsMilestone = 20;
const List<int> kMilestoneDays = [7, 14, 21, 28];

Future<int> getAttendanceStreakDay() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(kAttendanceStreakDayKey) ?? 1;
}

Future<String?> getAttendanceLastDate() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kAttendanceLastDateKey);
}

Future<int> getGoldenCoins() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(kGoldenCoinsKey) ?? 0;
}

Future<void> setGoldenCoins(int value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kGoldenCoinsKey, value);
}

/// 오늘 날짜 문자열 (yyyy-MM-dd)
String _todayString() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// 오늘 출석했는지
Future<bool> hasAttendedToday() async {
  final last = await getAttendanceLastDate();
  return last == _todayString();
}

/// 당일 "출석 화면 안 보기"를 선택한 경우 true (메인에서 오버레이 생략)
Future<bool> shouldSkipAttendanceOverlayToday() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kAttendanceSkipOverlayDateKey) == _todayString();
}

/// 출석 모달: 앱 실행 시 메인 전에 표시. 7x4 그리드, 순차 출석, 금연코인.
class AttendanceScreen extends StatefulWidget {
  final VoidCallback onClose;
  /// 출석 저장 직후 호출(예: Supabase push). 순환 import 방지용 콜백.
  final Future<void> Function()? onAttendanceRecorded;

  const AttendanceScreen({
    super.key,
    required this.onClose,
    this.onAttendanceRecorded,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

const String _coinAsset = 'assets/scoin.png';

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceApiService _attendanceApi = const AttendanceApiService();
  int _streakDay = 1;
  String? _lastDate;
  int _coins = 0;
  bool _loading = true;
  int? _justEarnedCoins;
  int? _justEarnedDay;
  bool _attendedThisSession = false;
  /// 출석 처리 후 당일 다시 출석창을 띄우지 않기 (닫을 때 prefs 저장)
  bool _hideOverlayRestOfDay = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(kAttendanceLastDateKey);
    final today = _todayString();
    int streak = prefs.getInt(kAttendanceStreakDayKey) ?? 1;

    if (last != null) {
      final lastDt = DateTime.tryParse(last);
      final todayDt = DateTime.parse(today);
      if (lastDt != null) {
        final diff = todayDt.difference(lastDt).inDays;
        if (diff > 1) {
          streak = 1;
          await prefs.setInt(kAttendanceStreakDayKey, 1);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _streakDay = streak;
      _lastDate = last;
      _coins = prefs.getInt(kGoldenCoinsKey) ?? 0;
      _loading = false;
    });
    unawaited(_syncAttendanceFromApiIfAvailable());
  }

  Future<void> _onTapDay(int day) async {
    final today = _todayString();
    if (_lastDate == today) return;
    int nextStreak = _streakDay;
    if (day != nextStreak) return;

    final coinsToAdd = kMilestoneDays.contains(day) ? kCoinsMilestone : kCoinsPerDay;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kAttendanceStreakDayKey, day == 28 ? 1 : day + 1);
    await prefs.setString(kAttendanceLastDateKey, today);
    final newCoins = (_coins + coinsToAdd);
    await prefs.setInt(kGoldenCoinsKey, newCoins);

    await cancelAttendanceReminder();

    if (!mounted) return;
    setState(() {
      _streakDay = day == 28 ? 1 : day + 1;
      _lastDate = today;
      _coins = newCoins;
      _justEarnedCoins = coinsToAdd;
      _justEarnedDay = day;
      _attendedThisSession = true;
      _hideOverlayRestOfDay = false;
    });

    final sync = widget.onAttendanceRecorded;
    if (sync != null) {
      unawaited(sync().catchError((Object _) {}));
    }
    unawaited(_checkInToApiIfAvailable(day));

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() {
        _justEarnedCoins = null;
        _justEarnedDay = null;
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${day}일 출석 완료! 금연코인 +$coinsToAdd (보유: $newCoins)'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  Future<void> _syncAttendanceFromApiIfAvailable() async {
    if (!SupabaseConfig.isConfigured) return;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final remote = await _attendanceApi.fetchState(accessToken: token);
      if (remote == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kGoldenCoinsKey, remote.coins);
      await prefs.setInt(kAttendanceStreakDayKey, remote.streakDay);
      if (remote.lastDate != null && remote.lastDate!.isNotEmpty) {
        await prefs.setString(kAttendanceLastDateKey, remote.lastDate!);
      }
      if (!mounted) return;
      setState(() {
        _coins = remote.coins;
        _streakDay = remote.streakDay;
        _lastDate = remote.lastDate;
      });
    } catch (_) {
      // 로컬 우선 정책: 실패 시 무시
    }
  }

  Future<void> _checkInToApiIfAvailable(int day) async {
    if (!SupabaseConfig.isConfigured) return;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final result = await _attendanceApi.checkIn(accessToken: token, day: day);
      if (result == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kGoldenCoinsKey, result.coins);
      await prefs.setInt(kAttendanceStreakDayKey, result.streakDay);
      if (result.lastDate != null && result.lastDate!.isNotEmpty) {
        await prefs.setString(kAttendanceLastDateKey, result.lastDate!);
      }
      if (!mounted) return;
      setState(() {
        _coins = result.coins;
        _streakDay = result.streakDay;
        _lastDate = result.lastDate;
      });
    } catch (_) {
      // 로컬 우선 정책: 실패 시 무시
    }
  }

  Future<void> _closeAttendance() async {
    if (_hideOverlayRestOfDay) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAttendanceSkipOverlayDateKey, _todayString());
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Material(
        color: Color(0xFF1E3A5F),
        child: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    final today = _todayString();
    final alreadyToday = _lastDate == today;
    final lastCheckedDay = alreadyToday
        ? (_streakDay == 1 ? 28 : _streakDay - 1)
        : _streakDay - 1;
    final tappableDay = alreadyToday ? null : _streakDay;

    return Material(
      color: const Color(0xFF1E3A5F),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '출석',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: () => _closeAttendance(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      _coinAsset,
                      width: 20,
                      height: 20,
                      errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 20),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '금연코인 $_coins개',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: kAttendanceDays,
                    itemBuilder: (context, index) {
                      final day = index + 1;
                      final checked = day <= lastCheckedDay;
                      final isTappable = tappableDay == day;
                      final isMilestone = kMilestoneDays.contains(day);
                      final coins = isMilestone ? kCoinsMilestone : kCoinsPerDay;
                      return _DayTile(
                        day: day,
                        coins: coins,
                        checked: checked,
                        isTappable: isTappable,
                        isMilestone: isMilestone,
                        onTap: () => _onTapDay(day),
                      );
                    },
                  ),
                ),
                if (alreadyToday || _attendedThisSession)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      children: [
                        if (alreadyToday)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              '오늘 출석을 완료했어요!',
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _hideOverlayRestOfDay,
                                onChanged: (v) {
                                  setState(() => _hideOverlayRestOfDay = v ?? false);
                                },
                                activeColor: const Color(0xFF5FC3E8),
                                side: const BorderSide(color: Colors.white54, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _hideOverlayRestOfDay = !_hideOverlayRestOfDay;
                                }),
                                child: Text(
                                  '하루 동안 출석체크 화면 보지 않기',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.92),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
            if (_justEarnedCoins != null && _justEarnedDay != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _CoinEarnedOverlay(
                    coins: _justEarnedCoins!,
                    day: _justEarnedDay!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoinEarnedOverlay extends StatefulWidget {
  final int coins;
  final int day;

  const _CoinEarnedOverlay({required this.coins, required this.day});

  @override
  State<_CoinEarnedOverlay> createState() => _CoinEarnedOverlayState();
}

class _CoinEarnedOverlayState extends State<_CoinEarnedOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.3, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          color: Colors.black.withOpacity(0.5 * _opacity.value),
          child: Center(
            child: Opacity(
              opacity: _opacity.value,
              child: ScaleTransition(
                scale: _scale,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A84B),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.6),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.day}일 출석!',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            _coinAsset,
                            width: 32,
                            height: 32,
                            errorBuilder: (_, __, ___) => const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 32),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '+${widget.coins}',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '금연코인을 획득했어요!',
                        style: TextStyle(
                          color: Colors.black87.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DayTile extends StatelessWidget {
  final int day;
  final int coins;
  final bool checked;
  final bool isTappable;
  final bool isMilestone;
  final VoidCallback onTap;

  const _DayTile({
    required this.day,
    required this.coins,
    required this.checked,
    required this.isTappable,
    required this.isMilestone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isTappable ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: checked
              ? const Color(0xFFD4A84B)
              : const Color(0xFF2A4365),
          borderRadius: BorderRadius.circular(10),
          border: isTappable
              ? Border.all(color: const Color(0xFF5FC3E8), width: 2)
              : null,
          boxShadow: isTappable
              ? [BoxShadow(color: const Color(0xFF5FC3E8).withOpacity(0.4), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day}일',
              style: TextStyle(
                color: checked ? Colors.black87 : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            if (checked)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF0D9488), size: 22)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    _coinAsset,
                    width: 12,
                    height: 12,
                    errorBuilder: (_, __, ___) => Icon(
                      isMilestone ? Icons.card_giftcard_rounded : Icons.diamond_rounded,
                      color: isTappable ? const Color(0xFF5FC3E8) : Colors.white38,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'x$coins',
                    style: TextStyle(
                      color: isTappable ? const Color(0xFF5FC3E8) : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
