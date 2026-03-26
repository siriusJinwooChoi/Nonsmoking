import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 스토어에 더 높은 버전이 있을 때, 로그인 후 한 번만 업데이트 안내 다이얼로그를 띄웁니다.
class UpdatePromptGate extends StatefulWidget {
  const UpdatePromptGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdatePromptGate> createState() => _UpdatePromptGateState();
}

class _UpdatePromptGateState extends State<UpdatePromptGate> {
  static const String _prefsKey = 'update_prompt_seen_for_version';

  static const String _androidPackageId = 'com.cjw.nonsmoking';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_maybeShowUpdateDialog()));
  }

  bool _isVersionLower(String installed, String store) {
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

  /// Play 스토어 HTML에서 현재 최신 버전 문자열을 최대한 파싱합니다.
  /// (네트워크/파싱 실패 시 null을 반환하고, 이 경우에는 업데이트 안내를 생략합니다.)
  Future<String?> _fetchPlayStoreVersionName() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;

    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$_androidPackageId&hl=ko&gl=US',
    );

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(uri);
      request.headers
        ..set('User-Agent', 'Mozilla/5.0 (compatible; FlutterApp)')
        ..set('Accept-Language', 'ko-KR');

      final response = await request.close();
      if (response.statusCode != 200) return null;

      // decode해서 문자열로 만들고, 버전 문자열을 정규식으로 찾습니다.
      final html = await response.transform(utf8.decoder).join();

      // 자주 쓰이는 형태: "softwareVersion":"1.0.10"
      final m1 = RegExp(r'"softwareVersion"\s*:\s*"([^"]+)"').firstMatch(html);
      if (m1 != null) return m1.group(1);

      // fallback: "현재 버전"/"Current Version" 근처에서 숫자 버전 추출
      final m2 = RegExp(
        r'(?:현재 버전|Current Version)[\s\S]{0,120}?([0-9]+(?:\.[0-9]+)+)',
      ).firstMatch(html);
      return m2?.group(1);
    } catch (_) {
      return null;
    }
  }

  Future<void> _maybeShowUpdateDialog() async {
    if (!mounted) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = info.version;
      final storeVersion = await _fetchPlayStoreVersionName();
      if (storeVersion == null) return;
      if (!_isVersionLower(installed, storeVersion)) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsKey) == storeVersion) return;
      if (!mounted) return;

      final goStore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('새 버전이 있어요'),
          content: Text(
            '스토어에 업데이트($storeVersion)가 출시되었습니다.\n지금 받으시겠어요?',
            style: AppTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('나중에'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('스토어로 이동'),
            ),
          ],
        ),
      );

      await prefs.setString(_prefsKey, storeVersion);
      if (goStore == true && mounted) {
        final uri = Uri.parse('https://play.google.com/store/apps/details?id=$_androidPackageId');
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('스토어를 열 수 없습니다.')),
          );
        }
      }
    } catch (_) {
      // PackageInfo 등 실패 시 무시
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
