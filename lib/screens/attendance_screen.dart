import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/remote_assets.dart';
import '../auth/bff_auth_service.dart';
import '../theme/app_theme.dart';
import '../notifications/daily_reminder_worker.dart';
import '../supabase/supabase_config.dart';
import '../api/attendance_api_service.dart';
import '../api/coins_api_service.dart';
/// 출석체크 1~28일, 7x4 그리드. 기본 15코인, 주말(토/일) 20코인.
const String kAttendanceStreakDayKey = 'attendance_streak_day';
const String kAttendanceLastDateKey = 'attendance_last_date';
const String kAttendanceHistoryDatesKey = 'attendance_history_dates_v1';
const String kGoldenCoinsKey = 'golden_coins';
/// 이 날짜(yyyy-MM-dd)에 "오늘 하루 출석 화면 안 보기"를 선택한 경우, 당일 재실행 시 출석 오버레이 생략
const String kAttendanceSkipOverlayDateKey = 'attendance_skip_overlay_date';
const int kAttendanceDays = 28;
const int kCoinsPerDay = 15;
const int kCoinsWeekend = 20;

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

const CoinsApiService _coinsApiService = CoinsApiService();

Future<int?> consumeCoinsIfPossible(int amount) async {
  if (amount <= 0) return await getGoldenCoins();
  final localCoins = await getGoldenCoins();
  if (localCoins < amount) return null;

  if (SupabaseConfig.isConfigured) {
    final token = await BffAuthService.instance.getValidAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final apiCoins = await _coinsApiService.consume(
          accessToken: token,
          amount: amount,
        );
        if (apiCoins != null) {
          await setGoldenCoins(apiCoins);
          return apiCoins;
        }
      } catch (_) {
        // 서버 실패 시 로컬 우선 fallback
      }
    }
  }

  final next = localCoins - amount;
  await setGoldenCoins(next);
  return next;
}

/// 오늘 날짜 문자열 (yyyy-MM-dd)
String _todayString() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

bool _isWeekend(DateTime dt) =>
    dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;

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

const String _scoinRemoteKey = 'scoin.png';

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceApiService _attendanceApi = const AttendanceApiService();
  int _streakDay = 1;
  String? _lastDate;
  int _coins = 0;
  bool _loading = true;
  int? _justEarnedCoins;
  int? _justEarnedDay;
  bool _attendedThisSession = false;
  bool _isCheckingIn = false;
  /// 출석 처리 후 당일 다시 출석창을 띄우지 않기 (닫을 때 prefs 저장)
  bool _hideOverlayRestOfDay = false;
  Set<String> _attendedDates = <String>{};
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month, 1);
    _load();
  }

  int _clampStreakDay(int v) => v.clamp(1, kAttendanceDays);

  Future<void> _load() async {
    // 서버 동기화는 네트워크 지연·무응답 시 화면이 멈추지 않도록 타임아웃
    if (SupabaseConfig.isConfigured) {
      try {
        await _syncAttendanceFromApiIfAvailable()
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // 로컬 우선: 타임아웃·오류 시에도 출석 UI는 계속 표시
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(kAttendanceLastDateKey);
    int streak = _clampStreakDay(prefs.getInt(kAttendanceStreakDayKey) ?? 1);

    final history = prefs.getStringList(kAttendanceHistoryDatesKey) ?? const <String>[];
    final normalizedHistory = await _backfillAttendanceHistoryFromQuitStart(
      prefs,
      history.toSet(),
    );

    if (!mounted) return;
    setState(() {
      _streakDay = _clampStreakDay(streak);
      _lastDate = last;
      _coins = prefs.getInt(kGoldenCoinsKey) ?? 0;
      _attendedDates = normalizedHistory;
      _loading = false;
    });
  }

  Future<Set<String>> _backfillAttendanceHistoryFromQuitStart(
    SharedPreferences prefs,
    Set<String> currentHistory,
  ) async {
    final startMs = prefs.getInt('startTime');
    if (startMs == null) return currentHistory;
    final now = DateTime.now();
    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    var day = DateTime(start.year, start.month, start.day);
    final end = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    if (day.isAfter(end)) return currentHistory;
    bool changed = false;
    while (!day.isAfter(end)) {
      final ymd =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if (!currentHistory.contains(ymd)) {
        currentHistory.add(ymd);
        changed = true;
      }
      day = day.add(const Duration(days: 1));
    }
    if (changed) {
      final sorted = currentHistory.toList()..sort();
      await prefs.setStringList(kAttendanceHistoryDatesKey, sorted);
    }
    return currentHistory;
  }

  DateTime get _earliestVisibleMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 2, 1);
  }

  bool get _canGoPrevMonth => _displayMonth.isAfter(_earliestVisibleMonth);
  bool get _canGoNextMonth {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    return _displayMonth.isBefore(thisMonth);
  }

  void _onTapDayBlocked(int day, {required bool alreadyToday, required int? tappableDay}) {
    if (alreadyToday) return;
    if (!mounted) return;
    final msg = tappableDay != null
        ? '지금은 $tappableDay일 칸을 눌러 출석할 수 있어요.'
        : '출석할 수 없습니다.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _onTapDay(int day) async {
    if (_isCheckingIn) return;
    final today = _todayString();
    if (_lastDate == today) return;
    int nextStreak = _streakDay;
    if (day != nextStreak) return;

    final coinsToAdd = _isWeekend(DateTime.now()) ? kCoinsWeekend : kCoinsPerDay;
    final nextDay = day == 28 ? 1 : day + 1;
    final newCoins = _coins + coinsToAdd;

    // 사용자가 눌렀을 때 즉시 반응하도록 UI를 먼저 낙관적 업데이트한다.
    setState(() {
      _isCheckingIn = true;
      _streakDay = nextDay;
      _lastDate = today;
      _coins = newCoins;
      _attendedDates = {..._attendedDates, today};
      _justEarnedCoins = coinsToAdd;
      _justEarnedDay = day;
      _attendedThisSession = true;
      _hideOverlayRestOfDay = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kAttendanceStreakDayKey, nextDay);
      await prefs.setString(kAttendanceLastDateKey, today);
      await prefs.setInt(kGoldenCoinsKey, newCoins);
      final history = (prefs.getStringList(kAttendanceHistoryDatesKey) ?? <String>[]).toSet();
      history.add(today);
      await prefs.setStringList(kAttendanceHistoryDatesKey, history.toList()..sort());
      await cancelAttendanceReminder();
    } catch (_) {
      // 로컬 우선 정책: 저장 실패 시에도 UI는 유지하고 다음 진입 동기화에서 보정
    } finally {
      if (mounted) {
        setState(() => _isCheckingIn = false);
      }
    }

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
    final token = await BffAuthService.instance.getValidAccessToken();
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
        _streakDay = _clampStreakDay(remote.streakDay);
        _lastDate = remote.lastDate;
      });
    } catch (_) {
      // 로컬 우선 정책: 실패 시 무시
    }
  }

  Future<void> _checkInToApiIfAvailable(int day) async {
    if (!SupabaseConfig.isConfigured) return;
    final token = await BffAuthService.instance.getValidAccessToken();
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
        _streakDay = _clampStreakDay(result.streakDay);
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
    final tappableDay = alreadyToday ? null : _streakDay;
    final now = DateTime.now();
    final firstOfMonth = _displayMonth;
    final daysInMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    final leadingEmpty = firstOfMonth.weekday % 7; // 일요일 시작
    final totalCells = leadingEmpty + daysInMonth;

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
                    RemoteAssetImage(
                      assetKey: _scoinRemoteKey,
                      width: 20,
                      height: 20,
                      error: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 20),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '금연코인 $_coins개',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A4365),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '출석 보상 안내: 매일 +$kCoinsPerDay코인'
                      ' (주말 토/일은 +$kCoinsWeekend코인)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _canGoPrevMonth
                            ? () {
                                setState(() {
                                  _displayMonth = DateTime(
                                    _displayMonth.year,
                                    _displayMonth.month - 1,
                                    1,
                                  );
                                });
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          '${_displayMonth.year}년 ${_displayMonth.month}월 출석 달력',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _canGoNextMonth
                            ? () {
                                setState(() {
                                  _displayMonth = DateTime(
                                    _displayMonth.year,
                                    _displayMonth.month + 1,
                                    1,
                                  );
                                });
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _WeekLabel('일'),
                      _WeekLabel('월'),
                      _WeekLabel('화'),
                      _WeekLabel('수'),
                      _WeekLabel('목'),
                      _WeekLabel('금'),
                      _WeekLabel('토'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: totalCells,
                    itemBuilder: (context, index) {
                      if (index < leadingEmpty) {
                        return const SizedBox.shrink();
                      }
                      final day = index - leadingEmpty + 1;
                      final dateStr =
                          '${_displayMonth.year}-${_displayMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                      final isToday = day == now.day &&
                          _displayMonth.year == now.year &&
                          _displayMonth.month == now.month;
                      final checked = _attendedDates.contains(dateStr) || (alreadyToday && isToday);
                      return Container(
                        decoration: BoxDecoration(
                          color: checked
                              ? const Color(0xFFD4A84B)
                              : const Color(0xFF2A4365),
                          borderRadius: BorderRadius.circular(10),
                          border: isToday
                              ? Border.all(color: const Color(0xFF5FC3E8), width: 2)
                              : null,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  color: checked ? Colors.black87 : Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Icon(
                                checked
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                size: 14,
                                color: checked
                                    ? const Color(0xFF0D9488)
                                    : Colors.white38,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_isCheckingIn || alreadyToday)
                          ? null
                          : () => _onTapDay(_streakDay),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        alreadyToday
                            ? '오늘 출석 완료'
                            : '오늘 출석하기 (${tappableDay}일차, +${_isWeekend(now) ? kCoinsWeekend : kCoinsPerDay} 코인)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5FC3E8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
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
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4A84B),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                '오늘 출석 완료! 금연코인이 지급되었습니다.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
                child: AbsorbPointer(
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

class _WeekLabel extends StatelessWidget {
  final String text;
  const _WeekLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
                          RemoteAssetImage(
                            assetKey: _scoinRemoteKey,
                            width: 32,
                            height: 32,
                            error: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 32),
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
  final VoidCallback onTapDisabled;

  const _DayTile({
    required this.day,
    required this.coins,
    required this.checked,
    required this.isTappable,
    required this.isMilestone,
    required this.onTap,
    required this.onTapDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isTappable ? onTap : onTapDisabled,
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
                  RemoteAssetImage(
                    assetKey: _scoinRemoteKey,
                    width: 12,
                    height: 12,
                    error: Icon(
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
