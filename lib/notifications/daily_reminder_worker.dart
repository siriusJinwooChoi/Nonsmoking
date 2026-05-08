import 'dart:convert';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

bool _notificationTzInitialized = false;

bool _mapLooksLikeReminderTime(Map<String, dynamic> m) {
  if (m.isEmpty) return false;
  return m.containsKey('h') ||
      m.containsKey('hour') ||
      m.containsKey('m') ||
      m.containsKey('minute');
}

/// [jsonDecode]·동기화 JSON 등으로 `Map<dynamic, dynamic>` 이 섞여도 스케줄되게 통일
/// DB/JSON에 `{}` 빈 객체가 끼어 있는 경우(스크린샷 사례) 잘못된 기본 시각 예약을 막음
List<Map<String, dynamic>> _reminderMapsFromDecodedList(List<dynamic> list) {
  final out = <Map<String, dynamic>>[];
  for (final item in list) {
    if (item is Map) {
      final m = Map<String, dynamic>.from(item);
      if (!_mapLooksLikeReminderTime(m)) continue;
      out.add(m);
    }
  }
  return out;
}

int _readReminderHour(Map<String, dynamic> m) {
  final v = m['h'] ?? m['hour'];
  if (v is int) return v.clamp(0, 23);
  if (v is num) return v.toInt().clamp(0, 23);
  return 9;
}

int _readReminderMinute(Map<String, dynamic> m) {
  final v = m['m'] ?? m['minute'];
  if (v is int) return v.clamp(0, 59);
  if (v is num) return v.toInt().clamp(0, 59);
  return 0;
}

/// WorkManager isolate 등 `main()`보다 먼저 도는 경로에서도 tz.local 사용 가능하도록
void ensureNotificationTimezoneInitialized() {
  if (_notificationTzInitialized) return;
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
  _notificationTzInitialized = true;
}

const String kIsConfiguredPrefsKey = 'isConfigured';

/// 온보딩 완료 후 알림 시간을 한 번도 저장한 적이 없으면 기본(09:00, 21:00)을 저장하고 예약합니다.
Future<void> ensureDefaultDailyReminderTimesIfUninitialized() async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(kIsConfiguredPrefsKey) ?? false)) return;
  if (prefs.containsKey(kReminderTimesKey)) return;

  await saveReminderTimes(const [
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 21, minute: 0),
  ]);
}

const String kDailyReminderTaskName = "daily_reminder_task";
const String kReasonReminderTaskName = "reason_reminder_task";
const String kDailyReminderUniqueWorkPrefix = "daily_reminder_slot_";
const String kReasonReminderUniqueWork = "reason_reminder_unique";
const int kDailyReminderNotificationIdBase = 1001;
const int kReasonReminderNotificationId = 2001;
const int kGoalReachedNotificationId = 3001;
const String kReminderTimesKey = 'reminderTimes';

/// 레거시 키. [fcmRemotePushEnabled]에서 [kFcmRemotePushEnabledKey]로 마이그레이션
const String kFcmRemoteDailyRemindersKey = 'fcmRemoteDailyReminders';

/// true 이면 일일·출석·담배수집 정각 알림을 서버 FCM으로만 보내고 해당 로컬 예약은 취소
const String kFcmRemotePushEnabledKey = 'fcmRemotePushEnabled';

bool fcmRemotePushEnabled(SharedPreferences prefs) {
  if (prefs.containsKey(kFcmRemotePushEnabledKey)) {
    return prefs.getBool(kFcmRemotePushEnabledKey) ?? false;
  }
  return prefs.getBool(kFcmRemoteDailyRemindersKey) ?? false;
}
const String kGoalDaysKey = 'goalDays';
const String kGoalCongratulatedDayKey = 'goalCongratulatedDay';
const String kSelectedReasonTextKey = 'selectedReasonText';
const String kReasonNotificationEnabledKey = 'reasonNotificationEnabled';

const String kInactivityReminderTaskName = 'inactivity_reminder_task';
const String kInactivityReminderUniqueWork = 'inactivity_reminder_unique';
const int kInactivityNotificationId = 4001;
const String kLastAppOpenTimeMsKey = 'lastAppOpenTimeMs';
const String kInactivityNotificationEnabledKey = 'inactivityNotificationEnabled';
const int kInactivityDaysThreshold = 3;
const int kMsPerDay = 24 * 60 * 60 * 1000;

const String kAttendanceReminderTaskName = 'attendance_reminder_task';
const String kAttendanceReminderUniqueWork = 'attendance_reminder_unique';
const int kAttendanceReminderNotificationId = 5001;
const String kAttendanceLastDateKey = 'attendance_last_date';
const String kAttendanceReminderEnabledKey = 'attendanceReminderEnabled';

const String kCigaretteCollectionReminderTaskName = 'cigarette_collection_reminder_task';
const String kCigaretteCollectionReminderUniqueWorkPrefix = 'cigarette_collection_reminder_';
const int kCigaretteCollectionReminderNotificationIdBase = 6001;
const String kCigaretteCollectionReminderEnabledKey = 'cigaretteCollectionReminderEnabled';
const String kCigaretteCollectionLastNotifiedWindowKey = 'cigarette_collection_last_notified_window';
const int kPatternReminderNotificationIdBase = 7001;
const String kPatternReminderEnabledKey = 'patternReminderEnabled';
const int kPatternReminderSlotMax = 5;
const String kPatternReminderSlotsKey = 'pattern_reminder_slots_v1';
const int kCigaretteCollectionWindowMinutes = 20;
const List<int> _cigaretteCollectionHours = [9, 12, 18, 22];

const InitializationSettings _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(),
  macOS: DarwinInitializationSettings(),
);

const DarwinNotificationDetails _defaultDarwinNotificationDetails =
    DarwinNotificationDetails(
  presentAlert: true,
  presentBadge: true,
  presentSound: true,
);

/// ✅ WorkManager 백그라운드 엔트리포인트 (반드시 top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (kDebugMode) {
      debugPrint('WorkManager fired: task=$task, input=$inputData');
    }

    if (task == kReasonReminderTaskName) {
      return _handleReasonReminder(inputData);
    }

    if (task == kInactivityReminderTaskName) {
      return _handleInactivityReminder(inputData);
    }

    if (task == kAttendanceReminderTaskName) {
      return _handleAttendanceReminder(inputData);
    }

    if (task == kCigaretteCollectionReminderTaskName) {
      return _handleCigaretteCollectionReminder(inputData);
    }

    if (task != kDailyReminderTaskName) {
      return Future.value(true);
    }

    // 구버전 WorkManager 예약: 표시 후 정시 알람(zoned)으로 이관
    return _handleDailyReminder(inputData);
  });
}

Future<bool> _handleReasonReminder(Map<String, dynamic>? inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kReasonNotificationEnabledKey) ?? false;
  if (!enabled) return true;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

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
    const NotificationDetails(
      android: androidDetails,
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );

  await scheduleReasonReminder();
  return true;
}

Future<bool> _handleDailyReminder(Map<String, dynamic>? inputData) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

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
    const NotificationDetails(
      android: androidDetails,
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );

  final mode = await resolveAndroidReminderScheduleMode();
  await scheduleZonedDailyReminderForSlot(
    hour: hour,
    minute: minute,
    slotIndex: slotIndex,
    androidScheduleMode: mode,
  );
  return true;
}

/// Android: 정확한 알람 권한이 없으면 `exactAllowWhileIdle` 예약이 전부 실패할 수 있어,
/// 가능 여부에 따라 모드를 고릅니다.
Future<AndroidScheduleMode> resolveAndroidReminderScheduleMode() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return AndroidScheduleMode.exactAllowWhileIdle;
  }
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;
  try {
    final canExact = await android.canScheduleExactNotifications();
    if (canExact == true) return AndroidScheduleMode.exactAllowWhileIdle;
  } catch (_) {}
  if (kDebugMode) {
    debugPrint(
      'resolveAndroidReminderScheduleMode: exact 알람 불가 → inexactAllowWhileIdle',
    );
  }
  return AndroidScheduleMode.inexactAllowWhileIdle;
}

/// 금연 리마인더: 매일 지정 시·분에 알람 예약 (exact 불가 기기는 inexact로 폴백)
Future<void> scheduleZonedDailyReminderForSlot({
  required int hour,
  required int minute,
  required int slotIndex,
  AndroidScheduleMode? androidScheduleMode,
}) async {
  ensureNotificationTimezoneInitialized();
  var mode =
      androidScheduleMode ?? await resolveAndroidReminderScheduleMode();

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

  const channel = AndroidNotificationChannel(
    'daily_reminder_channel',
    '금연 리마인더',
    description: '매일 설정된 시간에 금연 리마인더를 표시합니다.',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

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

  Future<void> scheduleWith(AndroidScheduleMode m) => plugin.zonedSchedule(
        kDailyReminderNotificationIdBase + slotIndex,
        '금연 리마인더 🌿',
        '오늘도 한 걸음! 금연을 이어가볼까요?',
        _nextInstanceAtTime(hour, minute),
        const NotificationDetails(
          android: androidDetails,
          iOS: _defaultDarwinNotificationDetails,
          macOS: _defaultDarwinNotificationDetails,
        ),
        androidScheduleMode: m,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

  try {
    await scheduleWith(mode);
  } on PlatformException catch (e) {
    if (mode == AndroidScheduleMode.exactAllowWhileIdle &&
        e.code == 'exact_alarms_not_permitted') {
      if (kDebugMode) {
        debugPrint(
          'scheduleZonedDailyReminderForSlot: exact 실패 → inexact 재시도 slot=$slotIndex',
        );
      }
      await scheduleWith(AndroidScheduleMode.inexactAllowWhileIdle);
    } else {
      rethrow;
    }
  }
}

/// 로컬 일일 리마인더(슬롯 0~19)만 취소
Future<void> cancelLocalDailyReminderSlotsOnly() async {
  for (var i = 0; i < 20; i++) {
    await Workmanager().cancelByUniqueName('$kDailyReminderUniqueWorkPrefix$i');
  }
  final plugin = FlutterLocalNotificationsPlugin();
  for (var i = 0; i < 20; i++) {
    await plugin.cancel(kDailyReminderNotificationIdBase + i);
  }
}

/// 서버 FCM 사용 여부. 켜면 일일·출석·담배수집·미접속·금연 이유 로컬 예약을 취소합니다.
Future<void> setFcmRemotePushEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kFcmRemotePushEnabledKey, enabled);
  await prefs.remove(kFcmRemoteDailyRemindersKey);
  if (enabled) {
    await cancelLocalDailyReminderSlotsOnly();
    await cancelCigaretteCollectionReminders();
    await cancelAttendanceReminder();
    await cancelInactivityReminderSchedule();
    await cancelReasonReminderSchedule();
  } else {
    await scheduleAllDailyReminders();
    await scheduleCigaretteCollectionReminders();
    await scheduleAttendanceReminderIfNeeded();
    if (prefs.getBool(kInactivityNotificationEnabledKey) ?? true) {
      await scheduleInactivityReminderOneOff(delayDays: kInactivityDaysThreshold);
    }
    if (prefs.getBool(kReasonNotificationEnabledKey) ?? false) {
      await scheduleReasonReminder();
    }
  }
}

/// 🔁 모든 알림 시간에 대해 정시 예약 (WorkManager 제거)
Future<void> scheduleAllDailyReminders() async {
  await ensureAndroidAlarmPermissionsForScheduling();

  final prefs = await SharedPreferences.getInstance();
  if (fcmRemotePushEnabled(prefs)) {
    await cancelLocalDailyReminderSlotsOnly();
    return;
  }

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

  final plugin = FlutterLocalNotificationsPlugin();
  for (var i = 0; i < 20; i++) {
    await plugin.cancel(kDailyReminderNotificationIdBase + i);
  }

  final scheduleMode = await resolveAndroidReminderScheduleMode();
  final maps = _reminderMapsFromDecodedList(list);
  if (maps.isEmpty && list.isNotEmpty && kDebugMode) {
    debugPrint(
      'scheduleAllDailyReminders: 알림 JSON을 Map으로 읽지 못해 예약이 0건입니다.',
    );
  }
  for (var i = 0; i < maps.length; i++) {
    final m = maps[i];
    final h = _readReminderHour(m);
    final mnt = _readReminderMinute(m);
    await scheduleZonedDailyReminderForSlot(
      hour: h,
      minute: mnt,
      slotIndex: i,
      androidScheduleMode: scheduleMode,
    );
  }
}

/// 금연 이유 알림 로컬 예약만 취소 (FCM 위임 시 prefs 유지)
Future<void> cancelReasonReminderSchedule() async {
  await Workmanager().cancelByUniqueName(kReasonReminderUniqueWork);
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.cancel(kReasonReminderNotificationId);
}

/// 비접속 알림 WorkManager 예약만 취소
Future<void> cancelInactivityReminderSchedule() async {
  await Workmanager().cancelByUniqueName(kInactivityReminderUniqueWork);
}

/// 금연 이유 알림 12:01 정시 예약 (예약 시점의 저장된 이유 문구 사용)
Future<void> scheduleReasonReminder() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kReasonNotificationEnabledKey) ?? false;
  if (!enabled) return;
  if (fcmRemotePushEnabled(prefs)) {
    await cancelReasonReminderSchedule();
    return;
  }

  await ensureAndroidAlarmPermissionsForScheduling();
  ensureNotificationTimezoneInitialized();

  final reasonText = prefs.getString(kSelectedReasonTextKey) ?? '오늘도 금연을 이어가세요!';
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

  const channel = AndroidNotificationChannel(
    'reason_reminder_channel',
    '금연 이유 알림',
    description: '매일 선택한 금연 이유를 알려드립니다.',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await Workmanager().cancelByUniqueName(kReasonReminderUniqueWork);
  await plugin.cancel(kReasonReminderNotificationId);

  const androidDetails = AndroidNotificationDetails(
    'reason_reminder_channel',
    '금연 이유 알림',
    channelDescription: '매일 선택한 금연 이유를 알려드립니다.',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  final reasonMode = await resolveAndroidReminderScheduleMode();
  Future<void> scheduleReason(AndroidScheduleMode m) => plugin.zonedSchedule(
        kReasonReminderNotificationId,
        '🌿 금연할 이유',
        reasonText,
        _nextInstanceAtTime(12, 1),
        const NotificationDetails(
          android: androidDetails,
          iOS: _defaultDarwinNotificationDetails,
          macOS: _defaultDarwinNotificationDetails,
        ),
        androidScheduleMode: m,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
  try {
    await scheduleReason(reasonMode);
  } on PlatformException catch (e) {
    if (reasonMode == AndroidScheduleMode.exactAllowWhileIdle &&
        e.code == 'exact_alarms_not_permitted') {
      await scheduleReason(AndroidScheduleMode.inexactAllowWhileIdle);
    } else {
      rethrow;
    }
  }
}

/// 플랫폼별 알림 권한 요청
Future<bool> requestNotificationPermissionIfNeeded() async {
  final plugin = FlutterLocalNotificationsPlugin();
  if (kIsWeb) return true;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final iosImpl = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl == null) return true;
    final granted = await iosImpl.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return granted ?? false;
  }

  if (defaultTargetPlatform == TargetPlatform.macOS) {
    final macImpl = plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macImpl == null) return true;
    final granted = await macImpl.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return granted ?? false;
  }

  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl == null) return true;
  final granted = await androidImpl.requestNotificationsPermission();
  return granted ?? false;
}

/// Android 12+ 정확한 알람(AlarmManager exact). 미허용 시 `zonedSchedule(..., exactAllowWhileIdle)` 가 조용히 실패할 수 있음.
Future<void> requestAndroidExactAlarmPermissionIfNeeded() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final plugin = FlutterLocalNotificationsPlugin();
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl == null) return;
  try {
    await androidImpl.requestExactAlarmsPermission();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('requestExactAlarmsPermission failed: $e\n$st');
    }
  }
}

/// 일일/이유 리마인더 등 exact 스케줄 전에 호출
Future<void> ensureAndroidAlarmPermissionsForScheduling() async {
  await requestNotificationPermissionIfNeeded();
  await requestAndroidExactAlarmPermissionIfNeeded();
}

Future<bool> _ensureNotificationPermissionGranted() async {
  if (kIsWeb) return true;

  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    // iOS/macOS는 상태 조회 API가 제한적이라 요청 API를 통해 현재 승인 상태를 확인합니다.
    return requestNotificationPermissionIfNeeded();
  }

  final plugin = FlutterLocalNotificationsPlugin();
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl == null) return true;
  try {
    final enabled = await androidImpl.areNotificationsEnabled();
    if (enabled == true) return true;
  } catch (_) {}
  return requestNotificationPermissionIfNeeded();
}

/// ✅ 알림 시간 목록 불러오기
Future<List<TimeOfDay>> getReminderTimes() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kReminderTimesKey);
  if (raw == null || raw.isEmpty) return [];

  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return _reminderMapsFromDecodedList(list)
        .map(
          (m) => TimeOfDay(
            hour: _readReminderHour(m),
            minute: _readReminderMinute(m),
          ),
        )
        .toList();
  } catch (_) {
    return [];
  }
}

/// ✅ 알림 시간 목록 저장 및 예약
Future<void> saveReminderTimes(List<TimeOfDay> times) async {
  await ensureAndroidAlarmPermissionsForScheduling();

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
  await plugin.initialize(_initSettings);

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
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );
  await prefs.setInt(kGoalCongratulatedDayKey, currentDays);
}

/// 3일 미접속 시 알림: 작업 실행 시 lastOpen 확인 후 알림 표시 및 24시간 후 재예약
Future<bool> _handleInactivityReminder(Map<String, dynamic>? inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kInactivityNotificationEnabledKey) ?? true;
  if (!enabled) return true;

  final lastMs = prefs.getInt(kLastAppOpenTimeMsKey);
  if (lastMs == null) return true;
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final daysSinceOpen = (nowMs - lastMs) / kMsPerDay;
  if (daysSinceOpen < kInactivityDaysThreshold) return true;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

  const channel = AndroidNotificationChannel(
    'inactivity_channel',
    '비접속 알림',
    description: '오랫동안 앱을 열지 않았을 때 알려드립니다.',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await plugin.show(
    kInactivityNotificationId,
    '금연은 잘 하고 계신가요?',
    '앱에서 금연현황을 확인해보세요!',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'inactivity_channel',
        '비접속 알림',
        channelDescription: '오랫동안 앱을 열지 않았을 때 알려드립니다.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );

  await scheduleInactivityReminderOneOff(delayDays: 1);
  return true;
}

/// 비접속 알림 1회 예약 (delayDays일 후 실행)
Future<void> scheduleInactivityReminderOneOff({int delayDays = 3}) async {
  // 알림 권한이 없어도 WorkManager 예약은 등록합니다. 실행 시점에 표시는 OS 정책을 따릅니다.
  final delay = Duration(days: delayDays);
  await Workmanager().registerOneOffTask(
    kInactivityReminderUniqueWork,
    kInactivityReminderTaskName,
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

/// 앱 열릴 때 호출: 마지막 접속 시간 저장 후 3일 뒤 비접속 알림 예약
Future<void> updateLastAppOpenAndScheduleInactivity() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kLastAppOpenTimeMsKey, DateTime.now().millisecondsSinceEpoch);
  await Workmanager().cancelByUniqueName(kInactivityReminderUniqueWork);
  if (fcmRemotePushEnabled(prefs)) {
    return;
  }
  await scheduleInactivityReminderOneOff(delayDays: kInactivityDaysThreshold);
}

/// 비접속 알림 설정값 저장 (설정 화면에서 호출)
Future<void> setInactivityNotificationEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kInactivityNotificationEnabledKey, enabled);
  if (!enabled) {
    await Workmanager().cancelByUniqueName(kInactivityReminderUniqueWork);
  } else if (fcmRemotePushEnabled(prefs)) {
    await cancelInactivityReminderSchedule();
  } else {
    await scheduleInactivityReminderOneOff(delayDays: kInactivityDaysThreshold);
  }
}

/// 비접속 알림 설정값 조회
Future<bool> getInactivityNotificationEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kInactivityNotificationEnabledKey) ?? true;
}

// ─── 출석체크 알림 (저녁 6시 이후 미출석 시 1시간마다) ───────────────────────

String _todayString() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

Future<bool> _handleAttendanceReminder(Map<String, dynamic>? inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kAttendanceReminderEnabledKey) ?? true;
  if (!enabled) return true;

  final lastDate = prefs.getString(kAttendanceLastDateKey);
  final today = _todayString();
  if (lastDate == today) return true;

  final now = DateTime.now();
  if (now.hour < 18) return true;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const channel = AndroidNotificationChannel(
    'attendance_reminder_channel',
    '출석 알림',
    description: '금연코인 획득을 위한 출석 알림',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await plugin.show(
    kAttendanceReminderNotificationId,
    '금연뱅크 출석',
    '금연코인 획득을 위해 금연뱅크에 출석하셔야 합니다.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'attendance_reminder_channel',
        '출석 알림',
        channelDescription: '금연코인 획득을 위한 출석 알림',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );

  await scheduleAttendanceReminderOnce();
  return true;
}

/// 1시간 후 출석 알림 1회 예약 (작업 실행 시 다시 1시간 후 예약하여 반복)
Future<void> scheduleAttendanceReminderOnce() async {
  const delay = Duration(hours: 1);
  await Workmanager().registerOneOffTask(
    kAttendanceReminderUniqueWork,
    kAttendanceReminderTaskName,
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

/// 출석 시 알림 해제
Future<void> cancelAttendanceReminder() async {
  await Workmanager().cancelByUniqueName(kAttendanceReminderUniqueWork);
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.cancel(kAttendanceReminderNotificationId);
}

/// 출석 알림 설정값 저장
Future<void> setAttendanceReminderEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kAttendanceReminderEnabledKey, enabled);
  if (!enabled) {
    await cancelAttendanceReminder();
  } else {
    await scheduleAttendanceReminderIfNeeded();
  }
}

/// 출석 알림 설정값 조회
Future<bool> getAttendanceReminderEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kAttendanceReminderEnabledKey) ?? true;
}

/// 앱 열릴 때: 18시 이후이고 오늘 미출석이면 1시간 후 출석 알림 예약
Future<void> scheduleAttendanceReminderIfNeeded() async {
  final enabled = await getAttendanceReminderEnabled();
  if (!enabled) return;
  final prefs = await SharedPreferences.getInstance();
  if (fcmRemotePushEnabled(prefs)) {
    await cancelAttendanceReminder();
    return;
  }
  if (prefs.getString(kAttendanceLastDateKey) == _todayString()) return;
  final now = DateTime.now();
  if (now.hour >= 18) await scheduleAttendanceReminderOnce();
}

// ─── 담배 수집 가능 시간 알림 (09:00, 12:00, 18:00, 22:00 정각) ─────────────────

Future<bool> _handleCigaretteCollectionReminder(Map<String, dynamic>? inputData) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kCigaretteCollectionReminderEnabledKey) ?? true;
  if (!enabled) return true;

  final hour = inputData?['hour'] as int? ?? 9;
  final now = DateTime.now();
  final windowStart = DateTime(now.year, now.month, now.day, hour, 0);
  final windowEnd = windowStart.add(const Duration(minutes: kCigaretteCollectionWindowMinutes));
  final isInExpectedWindow = !now.isBefore(windowStart) && now.isBefore(windowEnd);

  // WorkManager는 OEM/배터리 정책에 따라 지연 실행될 수 있어
  // 지정된 시간대(정각~20분) 밖에서 실행되면 이번 알림은 건너뜁니다.
  if (!isInExpectedWindow) {
    if (kDebugMode) {
      debugPrint(
        'Skip cigarette collection notification: now=$now, expected=$hour:00~$hour:20',
      );
    }
    await scheduleCigaretteCollectionReminderForHour(hour);
    return true;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

  const channel = AndroidNotificationChannel(
    'cigarette_collection_reminder_channel',
    '수집 시간 알림',
    description: '도감 수집 가능 시간 안내',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await plugin.show(
    kCigaretteCollectionReminderNotificationIdBase + hour,
    '수집 가능 시간',
    '지금부터 20분간 도감 수집을 시도할 수 있어요.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'cigarette_collection_reminder_channel',
        '수집 시간 알림',
        channelDescription: '도감 수집 가능 시간 안내',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );

  final windowId =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${hour.toString().padLeft(2, '0')}';
  await prefs.setString(kCigaretteCollectionLastNotifiedWindowKey, windowId);

  await scheduleCigaretteCollectionReminderForHour(hour);
  return true;
}

tz.TZDateTime _nextInstanceAtTime(int hour, int minute) {
  ensureNotificationTimezoneInitialized();
  final now = tz.TZDateTime.now(tz.local);
  var scheduled =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

/// 특정 시각(09/12/18/22)에 담배 수집 알림 1회 예약
Future<void> scheduleCigaretteCollectionReminderForHour(int hour) async {
  ensureNotificationTimezoneInitialized();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

  const channel = AndroidNotificationChannel(
    'cigarette_collection_reminder_channel',
    '수집 시간 알림',
    description: '도감 수집 가능 시간 안내',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  await plugin.zonedSchedule(
    kCigaretteCollectionReminderNotificationIdBase + hour,
    '수집 가능 시간',
    '지금부터 20분간 도감 수집을 시도할 수 있어요.',
    _nextInstanceAtTime(hour, 0),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'cigarette_collection_reminder_channel',
        '수집 시간 알림',
        channelDescription: '도감 수집 가능 시간 안내',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
    // 제조사/OS 정책에서 exact 알람이 누락되는 경우가 있어,
    // 담배수집은 20분 윈도우 특성상 inexact가 실사용 안정성이 더 높음.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
}

/// 담배 수집 알림 예약 취소 (설정 OFF·앱 데이터 정리 시)
Future<void> cancelCigaretteCollectionReminders() async {
  for (final hour in _cigaretteCollectionHours) {
    final uniqueName = '$kCigaretteCollectionReminderUniqueWorkPrefix$hour';
    await Workmanager().cancelByUniqueName(uniqueName);
  }
  final plugin = FlutterLocalNotificationsPlugin();
  for (final hour in _cigaretteCollectionHours) {
    await plugin.cancel(kCigaretteCollectionReminderNotificationIdBase + hour);
  }
}

/// 앱 실행 시 09:00, 12:00, 18:00, 22:00 담배 수집 알림 예약
Future<void> scheduleCigaretteCollectionReminders() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kCigaretteCollectionReminderEnabledKey) ?? true;
  if (!enabled) {
    await cancelCigaretteCollectionReminders();
    return;
  }
  if (fcmRemotePushEnabled(prefs)) {
    await cancelCigaretteCollectionReminders();
    return;
  }

  await requestNotificationPermissionIfNeeded();

  // 과거 WorkManager 기반 잔여 작업 정리
  for (final hour in _cigaretteCollectionHours) {
    final uniqueName = '$kCigaretteCollectionReminderUniqueWorkPrefix$hour';
    await Workmanager().cancelByUniqueName(uniqueName);
  }

  // 기존 예약 정리 후 정각 예약 재등록 (앱 종료 상태 보장)
  final plugin = FlutterLocalNotificationsPlugin();
  for (final hour in _cigaretteCollectionHours) {
    await plugin.cancel(kCigaretteCollectionReminderNotificationIdBase + hour);
  }

  for (final hour in _cigaretteCollectionHours) {
    await scheduleCigaretteCollectionReminderForHour(hour);
  }
}

/// 담배 수집 정각 알림 on/off (기본: 켜짐)
Future<bool> getCigaretteCollectionReminderEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kCigaretteCollectionReminderEnabledKey) ?? true;
}

Future<void> setCigaretteCollectionReminderEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kCigaretteCollectionReminderEnabledKey, enabled);
  if (!enabled) {
    await cancelCigaretteCollectionReminders();
  } else {
    await requestNotificationPermissionIfNeeded();
    await scheduleCigaretteCollectionReminders();
    await maybeNotifyCigaretteCollectionWindowOpened();
  }
}

String? _currentCigaretteCollectionWindowId(DateTime now) {
  for (final hour in _cigaretteCollectionHours) {
    final start = DateTime(now.year, now.month, now.day, hour, 0);
    final end = start.add(const Duration(minutes: kCigaretteCollectionWindowMinutes));
    if (!now.isBefore(start) && now.isBefore(end)) {
      final hh = hour.toString().padLeft(2, '0');
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-$hh';
    }
  }
  return null;
}

/// 앱 내부 기준: 수집 가능 구간에 "진입한 상태"면 해당 구간에 대해 1회 즉시 알림 발송
Future<void> maybeNotifyCigaretteCollectionWindowOpened() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(kCigaretteCollectionReminderEnabledKey) ?? true;
  if (!enabled) return;
  if (fcmRemotePushEnabled(prefs)) return;

  final granted = await _ensureNotificationPermissionGranted();
  if (!granted) return;

  final now = DateTime.now();
  final windowId = _currentCigaretteCollectionWindowId(now);
  if (windowId == null) return;

  final lastNotified = prefs.getString(kCigaretteCollectionLastNotifiedWindowKey);
  if (lastNotified == windowId) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);

  const channel = AndroidNotificationChannel(
    'cigarette_collection_reminder_channel',
    '수집 시간 알림',
    description: '도감 수집 가능 시간 안내',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  final hour = now.hour;
  await plugin.show(
    kCigaretteCollectionReminderNotificationIdBase + hour,
    '수집 가능 시간',
    '지금부터 20분간 도감 수집을 시도할 수 있어요.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'cigarette_collection_reminder_channel',
        '수집 시간 알림',
        channelDescription: '도감 수집 가능 시간 안내',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
  );

  await prefs.setString(kCigaretteCollectionLastNotifiedWindowKey, windowId);
}

/// 앱 실행 시 알림 권한 요청·핵심 스케줄(비접속/출석/담배수집·일일 리마인더) 재설정
///
/// 알림 권한을 거부한 경우에도 WorkManager·가능한 예약은 등록하고, 사용자가 설정에서 허용한 뒤
/// 앱을 다시 열면 [bootstrapCoreReminderSchedulesOnAppOpen]이 재호출되어 보완됩니다.
Future<void> bootstrapCoreReminderSchedulesOnAppOpen() async {
  ensureNotificationTimezoneInitialized();
  await ensureAndroidAlarmPermissionsForScheduling();
  await requestNotificationPermissionIfNeeded();

  await ensureDefaultDailyReminderTimesIfUninitialized();
  final times = await getReminderTimes();
  if (times.isNotEmpty) {
    try {
      await scheduleAllDailyReminders();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('bootstrap scheduleAllDailyReminders: $e\n$st');
      }
    }
  }

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kReasonNotificationEnabledKey) ?? false) {
    try {
      await scheduleReasonReminder();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('bootstrap scheduleReasonReminder: $e\n$st');
      }
    }
  }

  await updateLastAppOpenAndScheduleInactivity();
  await scheduleAttendanceReminderIfNeeded();
  await scheduleCigaretteCollectionReminders();
  await maybeNotifyCigaretteCollectionWindowOpened();
}

/// 사용자가 흡연/강한 욕구를 기록한 시각의 "다음날부터 매일 3분 전" 알림 예약
Future<void> schedulePatternReminder({
  required int patternId,
  required int hour,
  required int minute,
  required String nickname,
}) async {
  final enabled = await getPatternReminderEnabled();
  if (!enabled) return;
  ensureNotificationTimezoneInitialized();
  await ensureAndroidAlarmPermissionsForScheduling();
  final granted = await _ensureNotificationPermissionGranted();
  if (!granted) return;

  var notifyHour = hour;
  var notifyMinute = minute - 3;
  if (notifyMinute < 0) {
    notifyMinute += 60;
    notifyHour = (notifyHour - 1) % 24;
    if (notifyHour < 0) notifyHour += 24;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);
  const channel = AndroidNotificationChannel(
    'smoking_pattern_channel',
    '흡연 패턴 알림',
    description: '사용자 기록 기반 흡연욕구 예방 알림',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  final id = kPatternReminderNotificationIdBase + (patternId % 900);
  await plugin.cancel(id);

  const androidDetails = AndroidNotificationDetails(
    'smoking_pattern_channel',
    '흡연 패턴 알림',
    channelDescription: '사용자 기록 기반 흡연욕구 예방 알림',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  final bodyName = nickname.trim().isEmpty ? '회원' : nickname.trim();
  await plugin.zonedSchedule(
    id,
    '흡연 패턴 미리 알림',
    '($bodyName)님은 이 시간대에 담배를 피고 싶어하세요. 참아보세요!',
    _nextInstanceAtTime(notifyHour, notifyMinute),
    const NotificationDetails(
      android: androidDetails,
      iOS: _defaultDarwinNotificationDetails,
      macOS: _defaultDarwinNotificationDetails,
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
}

Future<void> schedulePatternRemindersFromSlots({
  required List<TimeOfDay> slots,
  required String nickname,
}) async {
  final capped = slots.take(kPatternReminderSlotMax).toList();
  // 알림 권한/OS 상태와 관계없이 계산된 패턴 시간대는 저장해 UI에서 확인 가능하게 한다.
  await setPatternReminderSlots(capped);

  final enabled = await getPatternReminderEnabled();
  if (!enabled) {
    await cancelPatternReminders();
    return;
  }
  ensureNotificationTimezoneInitialized();
  await ensureAndroidAlarmPermissionsForScheduling();
  final granted = await _ensureNotificationPermissionGranted();
  if (!granted) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);
  const channel = AndroidNotificationChannel(
    'smoking_pattern_channel',
    '흡연 패턴 알림',
    description: '사용자 기록 기반 흡연욕구 예방 알림',
    importance: Importance.high,
  );
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(channel);

  // 기존 패턴 예약은 먼저 정리한 뒤 최신 피크 슬롯만 다시 등록
  await cancelPatternReminders();

  const androidDetails = AndroidNotificationDetails(
    'smoking_pattern_channel',
    '흡연 패턴 알림',
    channelDescription: '사용자 기록 기반 흡연욕구 예방 알림',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  final bodyName = nickname.trim().isEmpty ? '회원' : nickname.trim();
  for (var i = 0; i < capped.length; i++) {
    var notifyHour = capped[i].hour;
    var notifyMinute = capped[i].minute - 3;
    if (notifyMinute < 0) {
      notifyMinute += 60;
      notifyHour = (notifyHour - 1) % 24;
      if (notifyHour < 0) notifyHour += 24;
    }
    final id = kPatternReminderNotificationIdBase + i;
    await plugin.zonedSchedule(
      id,
      '흡연 패턴 미리 알림',
      '($bodyName)님은 이 시간대에 담배를 피고 싶어하세요. 참아보세요!',
      _nextInstanceAtTime(notifyHour, notifyMinute),
      const NotificationDetails(
        android: androidDetails,
        iOS: _defaultDarwinNotificationDetails,
        macOS: _defaultDarwinNotificationDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}

Future<bool> getPatternReminderEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kPatternReminderEnabledKey) ?? true;
}

Future<void> cancelPatternReminders() async {
  final plugin = FlutterLocalNotificationsPlugin();
  for (var i = 0; i < 900; i++) {
    await plugin.cancel(kPatternReminderNotificationIdBase + i);
  }
}

Future<void> setPatternReminderSlots(List<TimeOfDay> slots) async {
  final prefs = await SharedPreferences.getInstance();
  final payload = slots
      .take(kPatternReminderSlotMax)
      .map((t) => {'h': t.hour, 'm': t.minute})
      .toList();
  await prefs.setString(kPatternReminderSlotsKey, jsonEncode(payload));
}

Future<void> clearPatternReminderSlots() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kPatternReminderSlotsKey);
}

Future<List<TimeOfDay>> getPatternReminderSlots() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kPatternReminderSlotsKey);
  if (raw == null || raw.isEmpty) return const <TimeOfDay>[];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return _reminderMapsFromDecodedList(list)
        .map((m) => TimeOfDay(hour: _readReminderHour(m), minute: _readReminderMinute(m)))
        .toList();
  } catch (_) {
    return const <TimeOfDay>[];
  }
}

Future<void> setPatternReminderEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kPatternReminderEnabledKey, enabled);
  if (!enabled) {
    await cancelPatternReminders();
    await clearPatternReminderSlots();
  }
}
