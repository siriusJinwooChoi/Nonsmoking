import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import '../theme/app_theme.dart';

/// 로그인 후 프로필에 표시할 닉네임을 한 번 설정합니다.
class NicknameSetupScreen extends StatefulWidget {
  const NicknameSetupScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.length < 2 || raw.length > 12) {
      setState(() => _error = '닉네임은 2~12자로 입력해 주세요.');
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      setState(() => _error = 'Supabase가 설정되지 않았습니다.');
      return;
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _error = '로그인 정보를 찾을 수 없습니다.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.from('profiles').update({
        'display_name': raw,
      }).eq('id', uid);
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('닉네임 설정'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '게임 랭킹에 표시될 닉네임을 정해 주세요.',
                style: AppTheme.titleMedium.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                maxLength: 12,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '닉네임',
                  hintText: '2~12자',
                  counterText: '',
                  filled: true,
                  fillColor: AppTheme.surfaceCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('시작하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
