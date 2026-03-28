import '../supabase/supabase_sync_service.dart';
import 'bff_auth_service.dart';
import 'bff_oauth_service.dart';

/// 로그인: BFF → Supabase Auth (anon 키는 서버에만 있음).
abstract final class AuthService {
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
    await BffAuthService.instance.signOut();
  }
}
