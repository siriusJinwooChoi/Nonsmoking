import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../api/api_config.dart';

/// Play 스토어 페이지의 앱 패키지 ID (Android)
const String kAndroidAppPackageId = 'com.cjw.nonsmoking';

Uri get playStoreAppUri =>
    Uri.parse('https://play.google.com/store/apps/details?id=$kAndroidAppPackageId');

/// 데스크톱 Chrome에 가까운 UA (Play 스토어가 JS 없는 봇 응답을 줄이는 데 도움이 되는 경우가 있음)
const String _kPlayStoreUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 서버에 아래 경로로 JSON을 두면 스토어 스크래핑 실패 시에도 버전 확인이 됩니다.
/// `GET {API_BASE_URL}/v1/public/app-version` → `{ "latest_version": "1.0.12" }`
Uri? _bffAppVersionUri() {
  final base = ApiConfig.baseUrl.trim();
  if (base.isEmpty) return null;
  return Uri.parse(base).replace(path: '/v1/public/app-version', queryParameters: {});
}

Future<String?> _fetchLatestVersionFromBff() async {
  final uri = _bffAppVersionUri();
  if (uri == null) return null;
  try {
    final res = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': _kPlayStoreUserAgent,
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final dynamic decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final v = decoded['latest_version'] as String?;
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  } catch (_) {
    return null;
  }
}

bool _looksLikeSemverName(String v) {
  final t = v.trim();
  if (t.isEmpty || t.length > 32) return false;
  return RegExp(r'^[0-9]+(\.[0-9]+){0,3}([a-zA-Z][a-zA-Z0-9]*)?$').hasMatch(t);
}

String? _extractVersionFromPlayHtml(String html) {
  if (html.length < 200) return null;

  final patterns = <RegExp>[
    RegExp(r'"softwareVersion"\s*:\s*"([^"]+)"'),
    RegExp(r'"softwareVersion\\?"\s*:\s*\\?"([^"\\]+)\\?"'),
    RegExp(r'itemprop="softwareVersion"[^>]*content="([^"]+)"'),
    RegExp(r'content="([^"]+)"[^>]*itemprop="softwareVersion"'),
    RegExp(r'"version"\s*:\s*"([0-9][0-9.]*[0-9])"'),
    RegExp(r'versionString"?\s*:\s*"?([0-9][0-9.]*[0-9])"?'),
    RegExp(r'Current version[^0-9A-Za-z]*([0-9]+(?:\.[0-9]+)+)', caseSensitive: false),
    RegExp(r'Current Version[^0-9A-Za-z]*([0-9]+(?:\.[0-9]+)+)', caseSensitive: false),
    RegExp(r'최신 버전[^0-9]*([0-9]+(?:\.[0-9]+)+)'),
    RegExp(r'현재 버전[^0-9]*([0-9]+(?:\.[0-9]+)+)'),
  ];

  for (final re in patterns) {
    final m = re.firstMatch(html);
    if (m != null) {
      final g = m.group(1);
      if (g != null && _looksLikeSemverName(g)) return g;
    }
  }

  // 일부 페이지: AF_initDataCallback 근처 숫자 버전
  final af = RegExp(r'\[\[\["([0-9]+\.[0-9]+(?:\.[0-9]+)?)"\]\]').firstMatch(html);
  if (af != null) {
    final g = af.group(1);
    if (g != null && _looksLikeSemverName(g)) return g;
  }

  return null;
}

Future<String?> _fetchPlayStoreHtmlOnce(Uri uri) async {
  try {
    final res = await http
        .get(
          uri,
          headers: {
            'User-Agent': _kPlayStoreUserAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
            'Cache-Control': 'no-cache',
            'Upgrade-Insecure-Requests': '1',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return res.body;
  } catch (_) {
    return null;
  }
}

/// Play 스토어 HTML 또는 BFF JSON에서 최신 버전 이름을 가져옵니다.
Future<String?> fetchPlayStoreLatestVersionName() async {
  if (kIsWeb) return null;
  if (!Platform.isAndroid) return null;

  // 1) 서버에 공개 엔드포인트가 있으면 가장 안정적
  final fromBff = await _fetchLatestVersionFromBff();
  if (fromBff != null) return fromBff;

  // 2) 스토어 HTML (구조 변경·지역·캡차 시 실패할 수 있음)
  final uris = <Uri>[
    Uri.parse(
      'https://play.google.com/store/apps/details?id=$kAndroidAppPackageId&hl=ko&gl=KR',
    ),
    Uri.parse(
      'https://play.google.com/store/apps/details?id=$kAndroidAppPackageId&hl=en&gl=US',
    ),
    Uri.parse(
      'https://play.google.com/store/apps/details?id=$kAndroidAppPackageId',
    ),
  ];

  for (final u in uris) {
    final html = await _fetchPlayStoreHtmlOnce(u);
    if (html == null) continue;
    final v = _extractVersionFromPlayHtml(html);
    if (v != null) return v;
  }

  return null;
}

/// 설치 버전이 스토어 버전보다 낮으면 true (동일·높으면 false).
bool isInstalledOlderThanStore(String installed, String store) {
  final a = installed.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final b = store.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final va = i < a.length ? a[i] : 0;
    final vb = i < b.length ? b[i] : 0;
    if (va < vb) return true;
    if (va > vb) return false;
  }
  return false;
}

Future<bool> openPlayStoreAppPage() async {
  return launchUrl(playStoreAppUri, mode: LaunchMode.externalApplication);
}
