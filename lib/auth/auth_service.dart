import 'package:flutter/foundation.dart';

import '../notifications/daily_reminder_worker.dart';
import '../supabase/supabase_sync_service.dart';
import 'apple_native_auth.dart';
import 'bff_auth_service.dart';
import 'bff_oauth_service.dart';

/// 로그인: BFF → Supabase Auth (anon 키는 서버에만 있음).
abstract final class AuthService {
  static Future<void> signInWithApple() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await AppleNativeAuth.signIn();
      await _afterInteractiveSignIn();
      return;
    }
    await BffOAuthService.signInWithProvider('apple');
    await _afterInteractiveSignIn();
  }

  static Future<void> signInWithGoogle() async {
    await BffOAuthService.signInWithProvider('google');
    await _afterInteractiveSignIn();
  }

  static Future<void> signInWithKakao() async {
    await BffOAuthService.signInWithProvider('kakao');
    await _afterInteractiveSignIn();
  }

  static Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await BffAuthService.instance.signInWithEmail(
      email: email,
      password: password,
    );
    await _afterInteractiveSignIn();
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
    await SupabaseSyncService.rememberCurrentAuthUidBeforeSignOut();
    await SupabaseSyncService.markPullRequiredOnNextLogin();
    await BffAuthService.instance.signOut();
  }

  static Future<void> deleteAccount() async {
    await SupabaseSyncService.rememberCurrentAuthUidBeforeSignOut();
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

  static Future<void> _afterInteractiveSignIn() async {
    // 로그인 직후에는 계정 전환 정렬 + post-login pull을 먼저 완료해
    // 화면 분기(온보딩/메인)가 이전 계정 로컬값으로 흔들리지 않게 한다.
    await SupabaseSyncService.prepareLocalStateForCurrentUser();
    await SupabaseSyncService.runPostLoginPullIfNeeded();
  }
}
