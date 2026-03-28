import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../supabase/supabase_config.dart';
import '../theme/app_theme.dart';
import 'auth_service.dart';
import 'bff_auth_service.dart';

Future<void> showEmailAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _EmailAuthSheet(),
  );
}

class _EmailAuthSheet extends StatefulWidget {
  const _EmailAuthSheet();

  @override
  State<_EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<_EmailAuthSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _passwordHint;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      if (!mounted) return;
      setState(() {
        _error = null;
        if (_tab.index == 1) {
          _passwordHint = _passwordFeedback(_password.text);
        } else {
          _passwordHint = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 서버 인증은 `email` 필드에 이메일 형식 문자열만 허용 — 앱에서는 로그인용 고유 ID로만 사용.
  bool _isValidLoginIdFormat(String value) {
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(value);
  }

  /// 기본 비밀번호 정책에 맞춤: 소문자·대문자·숫자·특수문자 포함, 8자 이상.
  /// (서버가 `weak_password` / reason `characters` 를 줄 때 대응)
  bool _meetsSignupPasswordPolicy(String password) {
    if (password.length < 8) return false;
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial =
        RegExp(r'[!@#$%^&*(),.?":{}|<>\-_+=~`/\\\[\]]').hasMatch(password);
    return hasLower && hasUpper && hasNumber && hasSpecial;
  }

  String _passwordGuideText() {
    return '회원가입 비밀번호: 8자 이상, 영문 소문자·대문자·숫자·특수문자를 모두 포함\n'
        '예: Abcdef12!';
  }

  String _passwordFeedback(String password) {
    if (password.isEmpty) return _passwordGuideText();
    if (_meetsSignupPasswordPolicy(password)) {
      return '사용 가능한 비밀번호입니다. (${password.length}자)';
    }
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial =
        RegExp(r'[!@#$%^&*(),.?":{}|<>\-_+=~`/\\\[\]]').hasMatch(password);
    final missing = <String>[
      if (!hasLower) '소문자',
      if (!hasUpper) '대문자',
      if (!hasNumber) '숫자',
      if (!hasSpecial) '특수문자',
    ];
    final lenHint = password.length < 8 ? ' (8자 이상 필요)' : '';
    return '부족: ${missing.join(', ')}$lenHint\n${_passwordGuideText()}';
  }

  Map<String, dynamic>? _bffDetailsMap(BffAuthException e) {
    final body = e.body;
    if (body is! Map) return null;
    final root = Map<String, dynamic>.from(body);
    final details = root['details'];
    if (details is Map) return Map<String, dynamic>.from(details);
    return root;
  }

  String _formatWeakPasswordReasonsFromDetails(Map<String, dynamic> d) {
    const mapKo = <String, String>{
      'characters':
          '소문자·대문자·숫자·특수문자를 모두 넣었는지 확인해 주세요.',
      'length': '비밀번호가 너무 짧습니다. 최소 길이를 맞춰 주세요.',
      'pwned': '다른 서비스에서 유출된 비밀번호입니다. 다른 비밀번호를 사용해 주세요.',
    };
    final reasons = d['reasons'];
    if (reasons is List) {
      final lines = reasons
          .map((r) => r is String ? (mapKo[r] ?? r) : r.toString())
          .toList();
      if (lines.isNotEmpty) return lines.join('\n');
    }
    final msg = (d['msg'] ?? d['message'])?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    return '비밀번호가 서버 정책에 맞지 않습니다. 규칙을 조정해 주세요.';
  }

  String _toUserError(Object e, {required bool isSignUp}) {
    final raw = e.toString().toLowerCase();

    if (e is BffAuthException) {
      final d = _bffDetailsMap(e);
      final errorCode =
          (d?['error_code'] ?? d?['error'])?.toString().toLowerCase();
      final message = (d?['msg'] ?? d?['message'] ?? e.messageFromServer)
          .toString()
          .toLowerCase();

      if (errorCode == 'weak_password') {
        return d != null
            ? _formatWeakPasswordReasonsFromDetails(d)
            : '비밀번호가 서버 정책에 맞지 않습니다. 다른 비밀번호를 사용해 주세요.';
      }
      if (errorCode == 'signup_disabled') {
        return '현재 회원가입이 비활성화되어 있습니다. 관리자에게 문의해 주세요.';
      }
      if (errorCode == 'email_provider_disabled') {
        return '서버에서 이메일(아이디) 로그인이 비활성화되어 있습니다. '
            '관리자에게 문의해 주세요.';
      }

      if (errorCode == 'user_already_exists' ||
          errorCode == 'email_exists' ||
          errorCode == 'identity_already_exists') {
        return '이미 사용 중인 아이디입니다. 「로그인」에서 시도해 주세요.';
      }
      if (message.contains('user already registered') ||
          message.contains('already registered') ||
          message.contains('already been registered')) {
        return '이미 사용 중인 아이디입니다. 「로그인」에서 시도해 주세요.';
      }

      if (message.contains('invalid') && message.contains('email')) {
        return '아이디는 이메일 형식으로 입력해 주세요. 예: user@example.com';
      }
      if (message.contains('invalid login credentials')) {
        return '아이디 또는 비밀번호가 올바르지 않습니다.';
      }
      if (e.statusCode == 429) {
        return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
      }

      final shown = e.messageFromServer.trim();
      if (shown.isNotEmpty && shown != e.toString()) {
        return shown;
      }
    }

    if (e is SocketException || raw.contains('socketexception')) {
      return '네트워크 연결을 확인해 주세요.';
    }

    if (raw.contains('validation_failed') && raw.contains('email')) {
      return '아이디는 이메일 형식으로 입력해 주세요. 예: user@example.com';
    }

    return isSignUp
        ? '회원가입에 실패했습니다. 입력한 정보를 확인해 주세요.'
        : '로그인에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _submit(bool isSignUp) async {
    if (!SupabaseConfig.isConfigured) {
      setState(() => _error = '서버 주소(API_BASE_URL)가 설정되지 않았습니다. 빌드 설정을 확인해 주세요.');
      return;
    }

    final id = _loginId.text.trim();
    final pw = _password.text;
    if (id.isEmpty) {
      setState(() => _error = '아이디를 입력해 주세요.');
      return;
    }
    if (!_isValidLoginIdFormat(id)) {
      setState(
        () => _error = '아이디는 이메일 형식으로 입력해 주세요. 예: user@example.com',
      );
      return;
    }
    if (pw.isEmpty) {
      setState(() => _error = '비밀번호를 입력해 주세요.');
      return;
    }
    if (isSignUp && !_meetsSignupPasswordPolicy(pw)) {
      setState(() {
        _error = '비밀번호가 규칙에 맞지 않습니다.';
        _passwordHint = _passwordFeedback(pw);
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _passwordHint = null;
    });
    try {
      if (isSignUp) {
        final res = await AuthService.signUpWithEmail(email: id, password: pw);
        final session = res['session'];
        if (session == null) {
          setState(() {
            _error = '가입은 되었으나 바로 로그인할 수 없습니다. '
                '이메일 인증이 필요한 경우 메일을 확인하거나, '
                '잠시 후 「로그인」에서 다시 시도해 주세요.';
          });
          return;
        }
        await AuthService.signOut();
        if (!mounted) return;
        _password.clear();
        _tab.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '회원가입이 완료되었습니다. 로그인 탭에서 로그인해 주세요.',
              style: GoogleFonts.notoSansKr(),
            ),
          ),
        );
        return;
      } else {
        await AuthService.signInWithEmail(email: id, password: pw);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = _toUserError(e, isSignUp: isSignUp));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tab,
                    labelColor: AppTheme.primary,
                    unselectedLabelColor: AppTheme.textMuted,
                    tabs: const [
                      Tab(text: '로그인'),
                      Tab(text: '회원가입'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '아이디·비밀번호는 이 기기에서 계정을 구분하고, 재설치 후 같은 아이디로 '
                    '데이터를 이어 쓰기 위한 로그인 정보입니다. 형식만 이메일처럼 입력하며, '
                    '실제 메일함으로 인증 메일을 보내지 않습니다.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      height: 1.45,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _loginId,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      labelText: '아이디',
                      helperText: '이메일 형식 (예: user@example.com)',
                      helperStyle: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                      hintText: 'user@example.com',
                      hintStyle: GoogleFonts.notoSansKr(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onChanged: (_) {
                      if (!mounted) return;
                      setState(() {
                        if (_tab.index == 1) {
                          _passwordHint = _passwordFeedback(_password.text);
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      hintText: _tab.index == 1 ? '영문/숫자/특수문자 조합' : null,
                      hintStyle: GoogleFonts.notoSansKr(),
                    ),
                  ),
                  if (_tab.index == 1) ...[
                    const SizedBox(height: 8),
                    Text(
                      _passwordHint ?? _passwordGuideText(),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        height: 1.4,
                        color: (_password.text.isNotEmpty &&
                                !_meetsSignupPasswordPolicy(_password.text))
                            ? AppTheme.warning
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () => _submit(_tab.index == 1),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _tab.index == 0 ? '로그인' : '회원가입',
                              style: GoogleFonts.notoSansKr(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
