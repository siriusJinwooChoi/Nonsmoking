import '../api/api_config.dart';

/// 필수 약관 동의(로컬). 서버 동기화는 [terms_accepted_at] 참고.
const String kTermsAgreedPrefsKey = 'terms_agreed_v1';

/// 클라우드(로그인·동기화) 사용 여부: **API Base URL**만 있으면 됨 (Supabase URL/anon 불필요).
abstract final class SupabaseConfig {
  static bool get isConfigured => ApiConfig.isConfigured;

  /// 카카오 개발자 콘솔 네이티브 앱 키 (AndroidManifest 등 — Dart 필수 아님).
  static const String kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '',
  );

  static const String kakaoOAuthScopes = String.fromEnvironment(
    'KAKAO_OAUTH_SCOPES',
    defaultValue: 'account_email',
  );

  /// OAuth 완료 후 앱 복귀 딥링크 (Supabase 대시보드 Redirect URLs에 등록).
  static const String oauthRedirectUrl =
      'com.cjw.nonsmoking://login-callback/';
}
