import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../auth/bff_auth_service.dart';
import '../firebase_options.dart';
import '../notifications/daily_reminder_worker.dart' as dw;

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

/// Android: 서버(FCM)로 **일일·출석·수집·미접속·금연 이유(12:01)** 알림을 보내고, 해당 로컬 예약은 끕니다.
/// (목표 달성 등 그 외는 로컬 유지)
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
    await _syncWithAuth();
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
        await dw.setFcmRemotePushEnabled(true);
        if (kDebugMode) {
          debugPrint('FcmDailyReminderService: token registered, remote push (daily/attendance/collection) on');
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
