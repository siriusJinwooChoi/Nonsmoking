import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/bff_auth_service.dart';
import 'api_config.dart';

/// AuthGate 빠른 진입용 — 닉네임 캐시 (계정별)
const String _kDisplayNameCache = 'bff_profile_display_name_cache_v1';
const String _kDisplayNameCacheUid = 'bff_profile_display_name_user_id_v1';

Uri _bffUri(String path) {
  final base = ApiConfig.baseUrl.endsWith('/')
      ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
      : ApiConfig.baseUrl;
  return Uri.parse('$base$path');
}

abstract final class BffProfileApi {
  static Future<Map<String, dynamic>?> fetchProfile() async {
    if (!ApiConfig.isConfigured) return null;
    final t = await BffAuthService.instance.getValidAccessToken();
    if (t == null) return null;
    final res = await http.get(
      _bffUri('/v1/profile'),
      headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'},
    );
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<bool> patchProfile({
    String? displayName,
    String? termsAcceptedAtIso,
  }) async {
    if (!ApiConfig.isConfigured) return false;
    final t = await BffAuthService.instance.getValidAccessToken();
    if (t == null) return false;
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (termsAcceptedAtIso != null) body['terms_accepted_at'] = termsAcceptedAtIso;
    if (body.isEmpty) return false;
    final res = await http.patch(
      _bffUri('/v1/profile'),
      headers: {
        'Authorization': 'Bearer $t',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return res.statusCode == 200;
  }

  static Future<void> cacheDisplayNameForCurrentUser(String displayName) async {
    final uid = BffAuthService.instance.userId;
    if (uid == null || uid.isEmpty) return;
    final n = displayName.trim();
    if (n.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayNameCache, n);
    await prefs.setString(_kDisplayNameCacheUid, uid);
  }

  static Future<void> clearDisplayNameCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDisplayNameCache);
    await prefs.remove(_kDisplayNameCacheUid);
  }

  /// 현재 로그인 uid와 캐시 uid가 같을 때만 닉네임 반환
  static Future<String?> readCachedDisplayNameForCurrentUser() async {
    final uid = BffAuthService.instance.userId;
    if (uid == null || uid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kDisplayNameCacheUid) != uid) return null;
    final n = prefs.getString(_kDisplayNameCache);
    if (n == null || n.trim().isEmpty) return null;
    return n.trim();
  }
}
