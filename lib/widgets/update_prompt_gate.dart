import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_update_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_maybeShowUpdateDialog()));
  }

  Future<void> _maybeShowUpdateDialog() async {
    if (!mounted) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = info.version;
      final storeVersion = await fetchPlayStoreLatestVersionName();
      if (storeVersion == null) return;
      if (!isInstalledOlderThanStore(installed, storeVersion)) return;

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
        final ok = await openPlayStoreAppPage();
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
