import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/bff_auth_service.dart';
import 'api_config.dart';

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
}
