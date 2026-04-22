import 'package:flutter/foundation.dart';

import '../notifications/daily_reminder_worker.dart';
import '../supabase/supabase_sync_service.dart';
import 'apple_native_auth.dart';
import 'bff_auth_service.dart';
import 'bff_oauth_service.dart';

/// 로그인: BFF → Supabase Auth (anon 키는 서버에만 있음).
abstract final class AuthService {
  static Future<void> signInWithApple() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleNativeAuth.signIn();
    }
    return BffOAuthService.signInWithProvider('apple');
  }

  static Future<void> signInWithGoogle() {
    return BffOAuthService.signInWithProvider('google');
  }

  static Future<void> signInWithKakao() {
    return BffOAuthService.signInWithProvider('kakao');
  }

  static Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return BffAuthService.instance.signInWithEmail(
      email: email,
      password: password,
    );
  }

  static Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return BffAuthService.instance.signUpWithEmail(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await SupabaseSyncService.markPullRequiredOnNextLogin();
    await SupabaseSyncService.clearLocalStateForAccountSwitch();
    await BffAuthService.instance.signOut();
  }

  static Future<void> deleteAccount() async {
    await BffAuthService.instance.deleteMyAccount();
    // 알림 해제·prefs 정리 중 하나가 실패해도 반드시 로컬 세션은 끊는다.
    try {
      try {
        await disableDailyReminder();
      } catch (_) {}
      try {
        await SupabaseSyncService.clearLocalStateForAccountSwitch();
      } catch (_) {}
    } finally {
      await BffAuthService.instance.signOut();
    }
  }
}
