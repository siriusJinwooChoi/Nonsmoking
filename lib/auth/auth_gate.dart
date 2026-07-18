import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase/supabase_config.dart';
import '../supabase/supabase_sync_service.dart';
import '../widgets/update_prompt_gate.dart';
import '../app_nav.dart';
import 'bff_auth_service.dart';
import 'login_screen.dart';
import '../screens/nickname_setup_screen.dart';
import 'terms_acceptance_screen.dart';
import '../api/bff_profile_api.dart';

/// API(BFF)가 설정된 경우에만 로그인·약관을 거친 뒤 [child]를 표시합니다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  int _termsVersion = 0;
  int _profileGateVersion = 0;
  int _sessionGateVersion = 0;
  bool _lastGateLoggedIn = false;
  String? _lastGateUid;

  @override
  void initState() {
    super.initState();
    _lastGateLoggedIn = BffAuthService.instance.isLoggedIn;
    _lastGateUid = BffAuthService.instance.userId;
    BffAuthService.instance.addListener(_onAuthChanged);
    _schedulePostLoginPull();
  }

  void _onAuthChanged() {
    final auth = BffAuthService.instance;
    final loggedIn = auth.isLoggedIn;
    final uid = auth.userId;
    final sessionChanged =
        loggedIn != _lastGateLoggedIn || uid != _lastGateUid;
    _lastGateLoggedIn = loggedIn;
    _lastGateUid = uid;

    if (mounted && sessionChanged) {
      setState(() {
        _sessionGateVersion++;
      });
    }
    if (sessionChanged) {
      _schedulePostLoginPull();
    }
  }

  void _schedulePostLoginPull() {
    if (!SupabaseConfig.isConfigured) return;
    if (!BffAuthService.instance.isLoggedIn) return;
    unawaited(SupabaseSyncService.runPostLoginPullIfNeeded());
  }

  @override
  void dispose() {
    BffAuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<bool> _termsFuture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kTermsAgreedPrefsKey) ?? false;
  }

  Future<bool> _needsIntroFuture() async {
    return SupabaseSyncService.shouldShowIntroFlow();
  }

  /// 캐시가 있으면 즉시 반환하고 서버는 백그라운드에서 맞춤. 없으면 네트워크를 기다림.
  Future<String?> _loadDisplayNameOrCachedFast() async {
    final cached = await BffProfileApi.readCachedDisplayNameForCurrentUser();
    if (cached != null && cached.isNotEmpty) {
      unawaited(_refreshProfileFromServerInBackground());
      return cached;
    }
    return _fetchProfileFromServerAndCache();
  }

  Future<String?> _fetchProfileFromServerAndCache() async {
    final row = await BffProfileApi.fetchProfile();
    if (row == null) return null;
    final n = row['display_name'] as String?;
    final name = n?.trim();
    if (name != null && name.isNotEmpty) {
      await BffProfileApi.cacheDisplayNameForCurrentUser(name);
      return name;
    }
    await BffProfileApi.clearDisplayNameCache();
    return null;
  }

  /// 캐시로 빠르게 들어온 뒤 서버와 불일치(닉네임 삭제 등)만 반영
  Future<void> _refreshProfileFromServerInBackground() async {
    try {
      final row = await BffProfileApi.fetchProfile();
      if (!mounted) return;
      if (row == null) return;

      final n = row['display_name'] as String?;
      final name = n?.trim();
      if (name == null || name.isEmpty) {
        await BffProfileApi.clearDisplayNameCache();
        if (mounted) setState(() => _profileGateVersion++);
        return;
      }
      await BffProfileApi.cacheDisplayNameForCurrentUser(name);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return UpdatePromptGate(child: widget.child);
    }

    return ListenableBuilder(
      listenable: BffAuthService.instance,
      builder: (context, _) {
        if (!BffAuthService.instance.isLoggedIn) {
          return const LoginScreen();
        }

        return FutureBuilder<void>(
          key: ValueKey('${BffAuthService.instance.userId}_$_sessionGateVersion'),
          future: SupabaseSyncService.prepareLocalStateForCurrentUser(),
          builder: (context, prepareSnap) {
            if (prepareSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return FutureBuilder<void>(
              key: ValueKey('post_login_pull_${BffAuthService.instance.userId}_$_sessionGateVersion'),
              future: SupabaseSyncService.runPostLoginPullIfNeeded(),
              builder: (context, pullSnap) {
                if (pullSnap.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return FutureBuilder<bool>(
                  key: ValueKey(_termsVersion),
                  future: _termsFuture(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!snap.data!) {
                      return TermsAcceptanceScreen(
                        onAgreed: () => setState(() => _termsVersion++),
                      );
                    }
                    return FutureBuilder<bool>(
                      key: ValueKey(
                        'needs_intro_${BffAuthService.instance.userId}_'
                        '${appRootGeneration.value}_$_sessionGateVersion',
                      ),
                      future: _needsIntroFuture(),
                      builder: (context, introSnap) {
                        if (!introSnap.hasData) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }

                        // 신규 계정은 사용자 입력(온보딩)부터 먼저 진행하고,
                        // 온보딩 완료 후에 닉네임 게이트를 거치도록 순서를 보장한다.
                        if (introSnap.data!) {
                          return UpdatePromptGate(child: widget.child);
                        }

                        return FutureBuilder<String?>(
                          key: ValueKey(_profileGateVersion),
                          future: _loadDisplayNameOrCachedFast(),
                          builder: (context, nameSnap) {
                            if (nameSnap.connectionState != ConnectionState.done) {
                              return const Scaffold(
                                body: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final displayName = nameSnap.data;
                            if (displayName == null || displayName.isEmpty) {
                              return NicknameSetupScreen(
                                onComplete: () => setState(() => _profileGateVersion++),
                              );
                            }
                            return UpdatePromptGate(child: widget.child);
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
