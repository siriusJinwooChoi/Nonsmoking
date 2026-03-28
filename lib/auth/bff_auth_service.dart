import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';

class BffAuthException implements Exception {
  BffAuthException(this.statusCode, this.body);
  final int statusCode;
  final dynamic body;

  String get messageFromServer {
    if (body is Map) {
      final m = body as Map<String, dynamic>;
      return (m['message'] as String?) ??
          (m['error'] as String?) ??
          (m['details'] is Map ? (m['details'] as Map)['msg']?.toString() : null) ??
          toString();
    }
    return toString();
  }

  @override
  String toString() => 'BffAuthException($statusCode)';
}

/// Supabase Auth는 앱이 아닌 BFF를 통해서만 사용합니다. 토큰은 Secure Storage에만 보관.
class BffAuthService extends ChangeNotifier {
  BffAuthService._();
  static final BffAuthService instance = BffAuthService._();

  static const _kAccess = 'bff_access_token';
  static const _kRefresh = 'bff_refresh_token';
  static const _kUid = 'bff_user_id';
  static const _kEmail = 'bff_user_email';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  String? _userEmail;

  bool get isLoggedIn =>
      _accessToken != null && _accessToken!.isNotEmpty;

  String? get userId => _userId;
  String? get userEmail => _userEmail;

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    return Uri.parse('$base$path');
  }

  int? _parseJwtExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is num) return exp.toInt();
    } catch (_) {}
    return null;
  }

  Future<void> restoreSession() async {
    if (!ApiConfig.isConfigured) return;
    _accessToken = await _storage.read(key: _kAccess);
    _refreshToken = await _storage.read(key: _kRefresh);
    _userId = await _storage.read(key: _kUid);
    _userEmail = await _storage.read(key: _kEmail);
    notifyListeners();
  }

  Future<void> applySessionFromAuthJson(Map<String, dynamic> body) async {
    final at = body['access_token'] as String?;
    final rt = body['refresh_token'] as String?;
    final user = body['user'];
    if (at == null || at.isEmpty) return;
    _accessToken = at;
    _refreshToken = rt;
    if (user is Map<String, dynamic>) {
      _userId = user['id'] as String?;
      _userEmail = user['email'] as String?;
    }
    await _storage.write(key: _kAccess, value: at);
    if (rt != null && rt.isNotEmpty) {
      await _storage.write(key: _kRefresh, value: rt);
    }
    if (_userId != null) await _storage.write(key: _kUid, value: _userId!);
    if (_userEmail != null) {
      await _storage.write(key: _kEmail, value: _userEmail!);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _userEmail = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kEmail);
    notifyListeners();
  }

  Future<void> _tryRefresh() async {
    final rt = _refreshToken;
    if (rt == null || rt.isEmpty) return;
    try {
      final res = await http.post(
        _uri('/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'refresh_token': rt}),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await applySessionFromAuthJson(body);
    } catch (_) {}
  }

  /// API 호출용. 만료 임박 시 리프레시 시도.
  Future<String?> getValidAccessToken() async {
    if (_accessToken == null || _accessToken!.isEmpty) return null;
    final exp = _parseJwtExp(_accessToken!);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && exp - now < 120) {
      await _tryRefresh();
    }
    return _accessToken;
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _uri('/v1/auth/sign-in'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200) {
      throw BffAuthException(res.statusCode, decoded);
    }
    await applySessionFromAuthJson(decoded as Map<String, dynamic>);
  }

  /// 반환: `{ user, session }` 형태 (세션 없을 수 있음)
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _uri('/v1/auth/sign-up'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200) {
      throw BffAuthException(res.statusCode, decoded);
    }
    return decoded as Map<String, dynamic>;
  }

  Future<void> completePkceOAuth({
    required String authCode,
    required String codeVerifier,
  }) async {
    final res = await http.post(
      _uri('/v1/auth/oauth/pkce'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'auth_code': authCode,
        'code_verifier': codeVerifier,
      }),
    );
    final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200) {
      throw BffAuthException(res.statusCode, decoded);
    }
    await applySessionFromAuthJson(decoded as Map<String, dynamic>);
  }
}
