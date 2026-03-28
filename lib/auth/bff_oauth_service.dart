import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../api/api_config.dart';
import '../supabase/supabase_config.dart';
import 'bff_auth_service.dart';

/// Google / Kakao: PKCE + 딥링크 `code` 를 BFF로 교환 (앱에 Supabase anon 불필요).
abstract final class BffOAuthService {
  static Completer<String?>? _codeCompleter;
  static String? _pendingVerifier;

  static void completeWithAuthCode(String? code) {
    final c = _codeCompleter;
    if (c == null || c.isCompleted) return;
    c.complete(code);
  }

  static String _randomVerifier() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final r = Random.secure();
    return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String _s256Challenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static Future<void> signInWithProvider(String provider) async {
    if (!ApiConfig.isConfigured) {
      throw StateError('API_BASE_URL not configured');
    }
    final verifier = _randomVerifier();
    final challenge = _s256Challenge(verifier);
    _pendingVerifier = verifier;
    _codeCompleter = Completer<String?>();

    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;

    final qp = <String, String>{
      'provider': provider,
      'redirect_to': SupabaseConfig.oauthRedirectUrl,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    };
    if (provider == 'kakao' && SupabaseConfig.kakaoOAuthScopes.trim().isNotEmpty) {
      qp['scopes'] = SupabaseConfig.kakaoOAuthScopes.trim();
    }

    final settingsUri = Uri.parse('$base/v1/auth/oauth/authorize-url')
        .replace(queryParameters: qp);

    final settingsRes = await http.get(
      settingsUri,
      headers: {'Accept': 'application/json'},
    );
    if (settingsRes.statusCode != 200) {
      throw Exception('authorize-url failed: ${settingsRes.statusCode}');
    }
    final body = jsonDecode(settingsRes.body) as Map<String, dynamic>;
    final authorizeUrl = body['url'] as String?;
    if (authorizeUrl == null || authorizeUrl.isEmpty) {
      throw Exception('missing authorize url');
    }

    final launched = await launchUrl(
      Uri.parse(authorizeUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _codeCompleter = null;
      _pendingVerifier = null;
      throw Exception('could_not_open_browser');
    }

    final code = await _codeCompleter!.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );
    _codeCompleter = null;
    final v = _pendingVerifier;
    _pendingVerifier = null;

    if (code == null || code.isEmpty || v == null) {
      throw Exception('oauth_cancelled');
    }

    await BffAuthService.instance.completePkceOAuth(
      authCode: code,
      codeVerifier: v,
    );
  }
}
