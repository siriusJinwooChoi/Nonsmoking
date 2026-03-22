/// Supabase 연결 정보.
///
/// 빌드 시 `--dart-define`으로 주입하는 것을 권장합니다.
/// 예:
/// `flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...`
///
/// **이메일·비밀번호 = 로그인용 계정 ID (실제 메일 인증 없음)**
/// - 대시보드 **Authentication → Providers → Email** 에서 **Confirm email(이메일 확인)** 을 **끄면**,
///   회원가입 직후 별도 메일 인증 없이 바로 로그인·세션 발급이 됩니다.
/// - Supabase Auth는 `email` 필드에 `user@domain` 형식만 요구하므로, 앱에서는 이를 **고유 ID**로만 씁니다.
///
/// **카카오 KOE205 (`profile_nickname` / `profile_image`)**
/// - Supabase Auth는 카카오 연동 시 **기본적으로** 닉네임·프로필 scope를 요청하는 동작이 있습니다.
///   [공식 문서](https://supabase.com/docs/guides/auth/social-login/auth-kakao) 에 따라 카카오 콘솔
///   **제품 설정 → 카카오 로그인 → 동의항목** 에서 **`profile_nickname`**, **`profile_image`**, **`account_email`** 을
///   **사용(필수 동의 등)** 으로 맞추는 것이 가장 확실합니다. (닉네임/프로필을 앱에 쓰지 않아도 동의만 켜 두면 됩니다.)
/// - 클라이언트에서는 `account_email` 위주로 scope를 넘깁니다.
///
/// **이메일(아이디) 로그인 (`email_provider_disabled`)**
/// - 대시보드 **Authentication → Providers → Email** 에서 제공자 **활성화(Enable)** 필수. (SQL로는 켤 수 없음)
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// 카카오 개발자 콘솔 **네이티브 앱 키** (Android `AndroidManifest` meta-data 등 네이티브 쪽과 동일).
  ///
  /// 로그인은 [OAuthProvider.kakao] Supabase OAuth를 쓰므로 Dart에서 필수는 아닙니다.
  /// 참조용으로만 쓸 때는 `--dart-define=KAKAO_NATIVE_APP_KEY=...` 로 주입 (소스에 기본값 두지 않음).
  static const String kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
    defaultValue: '',
  );

  /// 카카오 로그인 시 요청 scope (공백 구분). 카카오계정(이메일)만 쓸 때 `account_email`.
  static const String kakaoOAuthScopes = String.fromEnvironment(
    'KAKAO_OAUTH_SCOPES',
    defaultValue: 'account_email',
  );

  /// OAuth 완료 후 앱으로 돌아오기 위한 딥링크.
  /// Supabase 대시보드 Authentication → URL Configuration → Redirect URLs에 동일 문자열 등록 필요.
  static const String oauthRedirectUrl =
      'com.cjw.nonsmoking://login-callback/';
}

/// 필수 약관 동의(로컬). 서버 동기화는 [terms_accepted_at] 참고.
const String kTermsAgreedPrefsKey = 'terms_agreed_v1';
