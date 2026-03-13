import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String kDailyReminderTaskName = "daily_reminder_task";
const String kReasonReminderTaskName = "reason_reminder_task";
const String kDailyReminderUniqueWorkPrefix = "daily_reminder_slot_";
const String kReasonReminderUniqueWork = "reason_reminder_unique";
const int kDailyReminderNotificationIdBase = 1001;
const int kReasonReminderNotificationId = 2001;
const int kGoalReachedNotificationId = 3001;
const String kReminderTimesKey = 'reminderTimes';
const String kGoalDaysKey = 'goalDays';
const String kGoalCongratulatedDayKey = 'goalCongratulatedDay';
const String kSelectedReasonTextKey = 'selectedReasonText';
const String kReasonNotificationEnabledKey = 'reasonNotificationEnabled';

/// ✅ WorkManager 백그라운드 엔트리포인트 (반드시 top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    debugPrint("✅ WorkManager fired: task=$task, input=$inputData");

    if (task == kReasonReminderTaskName) {
      return _handleReasonReminder(inputData);
    }

    if (task != kDailyReminderTaskName) {
      return Future.value(true);
    }

    return _handleDailyReminder(inputData);
  });
}

Future<bool> _handleReasonReminder(Map<String, dynamic>? inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kReasonNotificationEnabledKey) ?? false;
  if (!enabled) return true;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const channel = AndroidNotificationChannel(
    'reason_reminder_channel',
    '금연 이유 알림',
    description: '매일 선택한 금연 이유를 알려드립니다.',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  final reasonText = prefs.getString(kSelectedReasonTextKey) ?? '오늘도 금연을 이어가세요!';
  const androidDetails = AndroidNotificationDetails(
    'reason_reminder_channel',
    '금연 이유 알림',
    channelDescription: '매일 선택한 금연 이유를 알려드립니다.',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  await plugin.show(
    kReasonReminderNotificationId,
    '🌿 금연할 이유',
    reasonText,
    const NotificationDetails(android: androidDetails),
  );

  await scheduleReasonReminder();
  return true;
}

Future<bool> _handleDailyReminder(Map<String, dynamic>? inputData) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const channel = AndroidNotificationChannel(
    'daily_reminder_channel',
    '금연 리마인더',
    description: '매일 설정된 시간에 금연 리마인더를 표시합니다.',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  final slotIndex = inputData?['slotIndex'] as int? ?? 0;
  final hour = inputData?['hour'] as int? ?? 9;
  final minute = inputData?['minute'] as int? ?? 0;

  const androidDetails = AndroidNotificationDetails(
    'daily_reminder_channel',
    '금연 리마인더',
    channelDescription: '매일 설정된 시간에 금연 리마인더를 표시합니다.',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    category: AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
  );

  await plugin.show(
    kDailyReminderNotificationIdBase + slotIndex,
    '금연 리마인더 🌿',
    '오늘도 한 걸음! 금연을 이어가볼까요?',
    const NotificationDetails(android: androidDetails),
  );

  await scheduleNextDailyReminder(hour: hour, minute: minute, slotIndex: slotIndex);
  return true;
}

/// ⏱ 다음 실행까지 안전한 딜레이 계산
Duration _computeDelayUntilNext({
  required int hour,
  required int minute,
}) {
  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, hour, minute);

  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }

  final diff = next.difference(now);
  final safeSeconds = max(diff.inSeconds, 60);
  return Duration(seconds: safeSeconds);
}

/// 🔁 단일 슬롯 다음 1회 작업 등록
Future<void> scheduleNextDailyReminder({
  required int hour,
  required int minute,
  int slotIndex = 0,
}) async {
  final delay = _computeDelayUntilNext(hour: hour, minute: minute);
  final uniqueName = '$kDailyReminderUniqueWorkPrefix$slotIndex';

  await Workmanager().registerOneOffTask(
    uniqueName,
    kDailyReminderTaskName,
    initialDelay: delay,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(
      networkType: NetworkType.not_required,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
    inputData: {
      'hour': hour,
      'minute': minute,
      'slotIndex': slotIndex,
    },
  );
}

/// 🔁 모든 알림 시간에 대해 작업 등록
Future<void> scheduleAllDailyReminders() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kReminderTimesKey);
  if (raw == null || raw.isEmpty) return;

  List<dynamic> list;
  try {
    list = jsonDecode(raw) as List<dynamic>;
  } catch (_) {
    return;
  }

  for (var i = 0; i < 20; i++) {
    await Workmanager().cancelByUniqueName('$kDailyReminderUniqueWorkPrefix$i');
  }

  for (var i = 0; i < list.length; i++) {
    final m = list[i];
    if (m is Map<String, dynamic>) {
      final h = m['h'] as int? ?? 9;
      final mnt = m['m'] as int? ?? 0;
      await scheduleNextDailyReminder(hour: h, minute: mnt, slotIndex: i);
    }
  }
}

/// 금연 이유 알림 12:01 예약
Future<void> scheduleReasonReminder() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kReasonNotificationEnabledKey) ?? false;
  if (!enabled) return;

  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, 12, 1);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  final diff = next.difference(now);
  final delay = Duration(seconds: max(diff.inSeconds, 60));

  await Workmanager().registerOneOffTask(
    kReasonReminderUniqueWork,
    kReasonReminderTaskName,
    initialDelay: delay,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(
      networkType: NetworkType.not_required,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
    inputData: {},
  );
}

/// Android 13+ 알림 권한 요청
Future<bool> requestNotificationPermissionIfNeeded() async {
  final plugin = FlutterLocalNotificationsPlugin();
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl == null) return true;
  final granted = await androidImpl.requestNotificationsPermission();
  return granted ?? false;
}

/// ✅ 알림 시간 목록 불러오기
Future<List<TimeOfDay>> getReminderTimes() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kReminderTimesKey);
  if (raw == null || raw.isEmpty) return [];

  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => TimeOfDay(
              hour: m['h'] as int? ?? 9,
              minute: m['m'] as int? ?? 0,
            ))
        .toList();
  } catch (_) {
    return [];
  }
}

/// ✅ 알림 시간 목록 저장 및 예약
Future<void> saveReminderTimes(List<TimeOfDay> times) async {
  await requestNotificationPermissionIfNeeded();

  final prefs = await SharedPreferences.getInstance();
  final list = times.map((t) => {'h': t.hour, 'm': t.minute}).toList();
  await prefs.setString(kReminderTimesKey, jsonEncode(list));

  if (times.isEmpty) {
    for (var i = 0; i < 20; i++) {
      await Workmanager().cancelByUniqueName('$kDailyReminderUniqueWorkPrefix$i');
    }
    final plugin = FlutterLocalNotificationsPlugin();
    for (var i = 0; i < 20; i++) {
      await plugin.cancel(kDailyReminderNotificationIdBase + i);
    }
  } else {
    await scheduleAllDailyReminders();
  }
}

/// ✅ 알림 한 개 추가 (기존 단일 호환용)
Future<void> enableDailyReminder(TimeOfDay time) async {
  final current = await getReminderTimes();
  if (current.any((t) => t.hour == time.hour && t.minute == time.minute)) return;
  current.add(time);
  await saveReminderTimes(current);
}

/// ❌ 모든 일반 알림 비활성화
Future<void> disableDailyReminder() async {
  await saveReminderTimes([]);
}

/// ❌ 금연 이유 알림 해지 (선택된 이유 ID도 해제해 UI 종 아이콘 반영)
Future<void> disableReasonReminder() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kReasonNotificationEnabledKey, false);
  await prefs.remove('selectedReasonId');
  await Workmanager().cancelByUniqueName(kReasonReminderUniqueWork);
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.cancel(kReasonReminderNotificationId);
}

/// 목표일 도달 시 축하 알림 (한 번만, 앱에서 호출)
Future<void> showGoalReachedNotificationIfNeeded(int currentDays, int? goalDays) async {
  if (goalDays == null || goalDays <= 0 || currentDays < goalDays) return;
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.getInt(kGoalCongratulatedDayKey);
  if (last != null && last >= goalDays) return;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const channel = AndroidNotificationChannel(
    'goal_channel',
    '목표 달성',
    description: '금연 목표일 달성 알림',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await plugin.show(
    kGoalReachedNotificationId,
    '🎉 목표 달성!',
    '목표일에 도착해서 축하드려요! 계속 힘내세요.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'goal_channel',
        '목표 달성',
        channelDescription: '금연 목표일 달성 알림',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
  await prefs.setInt(kGoalCongratulatedDayKey, currentDays);
}
