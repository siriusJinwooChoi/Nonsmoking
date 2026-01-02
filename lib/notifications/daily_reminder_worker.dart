import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String kDailyReminderTaskName = "daily_reminder_task";
const String kDailyReminderUniqueWork = "daily_reminder_unique_work";
const int kDailyReminderNotificationId = 1001;

/// ✅ WorkManager 백그라운드 엔트리포인트 (반드시 top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    debugPrint("✅ WorkManager fired: task=$task, input=$inputData");

    // 우리가 원하는 작업이 아니면 종료
    if (task != kDailyReminderTaskName) {
      return Future.value(true);
    }

    // 🔔 알림 플러그인 초기화
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await plugin.initialize(initSettings);

    // 🔔 알림 채널 생성
    const channel = AndroidNotificationChannel(
      'daily_reminder_channel',
      '금연 리마인더',
      description: '매일 설정된 시간에 금연 리마인더를 표시합니다.',
      importance: Importance.high,
    );

    final androidImpl =
    plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);

    // 🔔 알림 표시 (푸시처럼 보이는 Notification)
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

    const details = NotificationDetails(android: androidDetails);

    await plugin.show(
      kDailyReminderNotificationId,
      '금연 리마인더 🌿',
      '오늘도 한 걸음! 금연을 이어가볼까요?',
      details,
    );

    // ⏭ 다음 실행 예약
    final prefs = await SharedPreferences.getInstance();

    final hour =
        inputData?['hour'] as int? ?? prefs.getInt('reminderHour');
    final minute =
        inputData?['minute'] as int? ?? prefs.getInt('reminderMinute');

    if (hour != null && minute != null) {
      await scheduleNextDailyReminder(hour: hour, minute: minute);
    }

    return Future.value(true);
  });
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

  // ⚠️ WorkManager 안정성 확보용 (최소 60초)
  final safeSeconds = max(diff.inSeconds, 60);
  return Duration(seconds: safeSeconds);
}

/// 🔁 다음 1회 작업 등록 (체인 방식)
Future<void> scheduleNextDailyReminder({
  required int hour,
  required int minute,
}) async {
  final delay = _computeDelayUntilNext(hour: hour, minute: minute);

  await Workmanager().registerOneOffTask(
    kDailyReminderUniqueWork,
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
    },
  );
}

/// ✅ 알림 활성화 (시간 저장 + 첫 체인 시작)
Future<void> enableDailyReminder(TimeOfDay time) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('reminderHour', time.hour);
  await prefs.setInt('reminderMinute', time.minute);

  await scheduleNextDailyReminder(
    hour: time.hour,
    minute: time.minute,
  );
}

/// ❌ 알림 비활성화
Future<void> disableDailyReminder() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('reminderHour');
  await prefs.remove('reminderMinute');

  await Workmanager().cancelByUniqueName(kDailyReminderUniqueWork);

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.cancel(kDailyReminderNotificationId);
}