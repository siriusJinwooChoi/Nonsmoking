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
    // 로그아웃 전 미동기화 데이터를 서버에 먼저 저장
    try {
      await SupabaseSyncService.pushLocalToRemoteIfEligible();
    } catch (_) {}
    await SupabaseSyncService.rememberCurrentAuthUidBeforeSignOut();
    await SupabaseSyncService.markPullRequiredOnNextLogin();
    try {
      await cancelPatternReminders();
      await clearPatternReminderSlots();
    } catch (_) {}
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
    await SupabaseSyncService.prepareLocalStateForCurrentUser();

    // 서버에 온보딩이 완료되지 않은 계정(신규·미설정)은 intro를 반드시 보여준다.
    final remoteOnboardingDone =
        await SupabaseSyncService.remoteOnboardingCompleted();
    if (remoteOnboardingDone == false) {
      await SupabaseSyncService.markForceOnboardingOnce();
    }

    await SupabaseSyncService.runPostLoginPullIfNeeded();
  }
}
