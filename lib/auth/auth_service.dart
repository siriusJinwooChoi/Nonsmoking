import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import '../supabase/supabase_sync_service.dart';

/// Supabase Auth 래퍼 (Google / Kakao / 이메일).
///
/// **대시보드 설정**
/// - Authentication → Providers: Google, Kakao 활성화
/// - Email: **Confirm email 끄기** (로그인 ID만 쓸 때, [SupabaseConfig] 주석 참고)
/// - Redirect URLs에 [SupabaseConfig.oauthRedirectUrl] 추가
/// - Kakao: Client ID·Secret, scope는 [SupabaseConfig.kakaoOAuthScopes]·카카오 동의항목과 일치
abstract final class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
    );
  }

  static Future<void> signInWithKakao() async {
    final s = SupabaseConfig.kakaoOAuthScopes.trim().isEmpty
        ? 'account_email'
        : SupabaseConfig.kakaoOAuthScopes.trim();
    await _client.auth.signInWithOAuth(
      OAuthProvider.kakao,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
      scopes: s,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: SupabaseConfig.oauthRedirectUrl,
    );
  }

  static Future<void> signOut() async {
    await SupabaseSyncService.markPullRequiredOnNextLogin();
    await _client.auth.signOut();
  }
}
