import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/quit_rooms_api_service.dart';

import '../api/api_config.dart';
import '../auth/bff_auth_service.dart';
import '../firebase_options.dart';
import '../app_nav.dart';
import '../notifications/daily_reminder_worker.dart' as dw;
import '../screens/quit_room/quit_room_detail_screen.dart';
import '../screens/quit_room/quit_room_models.dart';

/// 백그라운드에서 수신 시 Firebase 초기화 (FCM)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Uri _bffUri(String path) {
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  return Uri.parse('$base$path');
}

/// Android·iOS: FCM 토큰이 서버에 등록되면 서버 스케줄로 **일일·출석·수집·미접속·금연 이유(12:01)** 등을 보내고
/// 해당 항목의 로컬 예약은 끕니다. **흡연 패턴 미리 알림**은 기기 시각 기반이라 로컬 예약을 유지합니다.
class FcmDailyReminderService {
  FcmDailyReminderService._();
  static final FcmDailyReminderService instance = FcmDailyReminderService._();

  bool _started = false;
  String? _lastUploadedToken;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!ApiConfig.isConfigured) return;
    if (kIsWeb) {
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      _lastUploadedToken = null;
      unawaited(_uploadToken(t));
    });

    BffAuthService.instance.addListener(_authListener);
    FirebaseMessaging.onMessageOpenedApp.listen(_onQuitRoomPushOpened);
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _onQuitRoomPushOpened(m);
    });
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    await _syncWithAuth();
  }

  void _onForegroundMessage(RemoteMessage message) {
    final type = message.data['type'] as String?;
    if (type != 'quit_room_sos') return;
    final roomId = message.data['room_id'] as String?;
    if (roomId == null) return;
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message.notification?.body ?? '금연방 SOS가 도착했어요'),
        action: SnackBarAction(
          label: '보기',
          onPressed: () => _openQuitRoomById(roomId),
        ),
      ),
    );
  }

  Future<void> _onQuitRoomPushOpened(RemoteMessage message) async {
    final type = message.data['type'] as String?;
    if (type != 'quit_room_sos') return;
    final roomId = message.data['room_id'] as String?;
    if (roomId == null) return;
    await _openQuitRoomById(roomId);
  }

  Future<void> _openQuitRoomById(String roomId) async {
    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return;

    final serverRooms = await QuitRoomsApiService.fetchRooms();
    Map<String, dynamic>? match;
    if (serverRooms != null) {
      match = serverRooms.where((r) => r['id'] == roomId).firstOrNull;
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = decodeRooms(prefs.getString(kQuitRoomsKey));
    QuitRoom? room;
    if (match != null) {
      room = QuitRoom.fromServerJson(match);
    } else {
      room = cached.where((r) => r.id == roomId).firstOrNull;
    }
    if (room == null) return;

    await nav.push(
      MaterialPageRoute(builder: (_) => QuitRoomDetailScreen(room: room!)),
    );
  }

  void _authListener() {
    unawaited(_syncWithAuth());
  }

  Future<void> _syncWithAuth() async {
    if (!BffAuthService.instance.isLoggedIn) {
      _lastUploadedToken = null;
      await dw.setFcmRemotePushEnabled(false);
      return;
    }
    await _uploadCurrentDeviceToken();
  }

  Future<void> _uploadCurrentDeviceToken() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await messaging.getAPNSToken();
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _uploadToken(token);
  }

  Future<void> _uploadToken(String token) async {
    if (token == _lastUploadedToken) return;
    final access = await BffAuthService.instance.getValidAccessToken();
    if (access == null || access.isEmpty) return;

    try {
      final res = await http.put(
        _bffUri('/v1/devices/fcm-token'),
        headers: {
          'Authorization': 'Bearer $access',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'token': token}),
      );
      if (res.statusCode == 200) {
        _lastUploadedToken = token;
        // Android·iOS 동일: 서버 FCM 크론에 위임하고 로컬 중복 예약은 끈다.
        await dw.setFcmRemotePushEnabled(true);
        if (kDebugMode) {
          debugPrint(
            'FcmDailyReminderService: token registered, remotePush=true',
          );
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('FcmDailyReminderService: upload failed $e\n$st');
      }
    }
  }

  /// [BffAuthService.signOut] 직전 호출 — 서버 토큰 제거 후 로컬 알림 재예약
  Future<void> onBeforeSignOut() async {
    final access = await BffAuthService.instance.getValidAccessToken();
    if (access != null && access.isNotEmpty) {
      try {
        await http.delete(
          _bffUri('/v1/devices/fcm-token'),
          headers: {
            'Authorization': 'Bearer $access',
            'Accept': 'application/json',
          },
        );
      } catch (_) {}
    }
    _lastUploadedToken = null;
    await dw.setFcmRemotePushEnabled(false);
  }
}
