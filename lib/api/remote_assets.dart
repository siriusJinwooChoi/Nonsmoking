import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// 서버 `public/app-assets` 를 `/static/` 으로 노출할 때의 URL·담배갑 목록 API.
abstract final class RemoteAssets {
  static const prefsMigrationKey = 'remote_assets_cigarette_path_v1';
  static const _collectedPrefsKey = 'collected_cigarette_assets';
  static const _sessionAssetPrefsKey = 'cigarette_collect_session_asset';

  static String get staticBaseUrl {
    final b = ApiConfig.baseUrl.trim();
    if (b.isEmpty) return '';
    final trimmed = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    return '$trimmed/static';
  }

  static Uri urlForKey(String key) {
    final base = staticBaseUrl;
    final k = key.startsWith('/') ? key.substring(1) : key;
    return Uri.parse('$base/$k');
  }

  static Uri get _cigarettesManifestUri {
    final b = ApiConfig.baseUrl.trim();
    final trimmed = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    return Uri.parse('$trimmed/v1/assets/cigarettes');
  }

  /// 예전 로컬 에셋 경로 `assets/cigarettes/x.png` → 원격 키 `cigarettes/x.png`
  static String normalizeCigaretteKey(String path) {
    final p = path.trim();
    if (p.startsWith('assets/cigarettes/')) {
      return p.substring('assets/'.length);
    }
    return p;
  }

  static List<String> normalizeCigaretteKeyList(List<String> raw) {
    final out = raw.map(normalizeCigaretteKey).toSet().toList()..sort();
    return out;
  }

  /// 기기에 남아 있던 `assets/cigarettes/...` 키를 한 번 정규화합니다.
  static Future<void> migrateLegacyCigarettePathsInPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefsMigrationKey) ?? false) return;

    var changed = false;

    final collected = prefs.getStringList(_collectedPrefsKey) ?? <String>[];
    final nCollected = normalizeCigaretteKeyList(collected);
    final needsCollectedWrite = collected.length != nCollected.length ||
        collected.any((e) => normalizeCigaretteKey(e) != e);
    if (needsCollectedWrite) {
      await prefs.setStringList(_collectedPrefsKey, nCollected);
      changed = true;
    }

    final sa = prefs.getString(_sessionAssetPrefsKey);
    if (sa != null && sa.isNotEmpty) {
      final n = normalizeCigaretteKey(sa);
      if (n != sa) {
        await prefs.setString(_sessionAssetPrefsKey, n);
        changed = true;
      }
    }

    await prefs.setBool(prefsMigrationKey, true);
    if (changed && kDebugMode) {
      debugPrint('[RemoteAssets] migrated legacy cigarette asset paths in prefs');
    }
  }

  /// 서버 `GET /v1/assets/cigarettes` → `cigarettes/파일명` 목록
  static Future<List<String>> fetchCigarettePackKeys() async {
    if (!ApiConfig.isConfigured) return const [];
    try {
      final res = await http.get(
        _cigarettesManifestUri,
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final items = decoded['items'];
      if (items is! List) return const [];
      return items.map((e) => e.toString()).toList()..sort();
    } catch (_) {
      return const [];
    }
  }
}

/// `GET {API}/static/{assetKey}` 이미지
class RemoteAssetImage extends StatelessWidget {
  const RemoteAssetImage({
    super.key,
    required this.assetKey,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.error,
  });

  final String assetKey;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    if (!ApiConfig.isConfigured || RemoteAssets.staticBaseUrl.isEmpty) {
      return error ??
          const Icon(Icons.cloud_off_outlined, color: Colors.grey);
    }
    final url = RemoteAssets.urlForKey(assetKey).toString();
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      errorBuilder: (_, __, ___) =>
          error ?? const Icon(Icons.broken_image_outlined, color: Colors.grey),
    );
  }
}
