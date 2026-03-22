import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import '../supabase/supabase_sync_service.dart';
import 'login_screen.dart';
import 'terms_acceptance_screen.dart';

/// Supabase가 설정된 경우에만 로그인·약관을 거친 뒤 [child]를 표시합니다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSub;
  int _termsVersion = 0;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.isConfigured) {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.session != null &&
            (data.event == AuthChangeEvent.signedIn ||
                data.event == AuthChangeEvent.initialSession)) {
          unawaited(SupabaseSyncService.runPostLoginPullIfNeeded());
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<bool> _termsFuture() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kTermsAgreedPrefsKey) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return widget.child;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return const LoginScreen();
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
        return widget.child;
      },
    );
  }
}
