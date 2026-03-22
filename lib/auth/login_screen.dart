import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'auth_service.dart';
import 'email_auth_bottom_sheet.dart';

/// 소셜 로그인 + 아이디·비밀번호 (참고 UI: 상단 브랜딩 + 하단 화이트 시트).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _t1 = false;
  bool _t2 = false;
  bool _t3 = false;
  bool _t4 = false;
  String? _busy; // kakao | google | null

  bool get _termsOk => _t1 && _t2 && _t3 && _t4;

  Future<void> _run(String tag, Future<void> Function() fn) async {
    if (!_termsOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('필수 약관에 모두 동의해 주세요.')),
      );
      return;
    }
    setState(() => _busy = tag);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인에 실패했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const sheet = Color(0xFFFBFDFC);

    return Scaffold(
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF0FDFA),
                    Color(0xFFE8F5F2),
                    Color(0xFFDFF0EB),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(child: _LoginAmbientDecor()),
          /// 배경(그라데이션 + 브랜딩)은 시트와 독립 — 상단에 고정, 시트 드래그와 무관하게 움직이지 않음
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '금연뱅크',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF134E4A),
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          height: 1.4,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          const TextSpan(text: '매일 조금씩,\n'),
                          TextSpan(
                            text: '더 건강한 나',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(text: '를 만드는 금연 습관'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _bubble(
                      icon: Icons.savings_outlined,
                      text: '오늘 아낀 돈 얼마일까?',
                      alignLeft: true,
                    ),
                    _bubble(
                      icon: Icons.favorite_border,
                      text: '폐 건강이 좋아지고 있어요!',
                      alignLeft: false,
                    ),
                    _bubble(
                      icon: Icons.emoji_events_outlined,
                      text: '연속 출석 도전 중!',
                      alignLeft: true,
                    ),
                    _bubble(
                      icon: Icons.park_outlined,
                      text: '나무가 무럭무럭 자라요',
                      alignLeft: false,
                    ),
                    const SizedBox(height: 28),
                    _buildBackgroundTipCards(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _LoginBottomMotto(),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.08,
            maxChildSize: 0.95,
            snap: true,
            snapSizes: const [0.08, 0.55, 0.88],
            expand: true,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: Container(
                  decoration: BoxDecoration(
                    color: sheet,
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.85)),
                      left: BorderSide(color: Colors.white.withValues(alpha: 0.85)),
                      right: BorderSide(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, -6),
                      ),
                      const BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 16,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      MediaQuery.paddingOf(context).bottom + 12,
                    ),
                    physics: const ClampingScrollPhysics(),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '시작하기 전에',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '필수 항목에 동의 후 로그인할 수 있어요.',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _termRow('이용 약관 동의 (필수)', _t1, (v) => setState(() => _t1 = v)),
                      _termRow('개인정보 수집·이용 동의 (필수)', _t2, (v) => setState(() => _t2 = v)),
                      _termRow('민감정보 수집·이용 동의 (필수)', _t3, (v) => setState(() => _t3 = v)),
                      _termRow('만 14세 이상입니다 (필수)', _t4, (v) => setState(() => _t4 = v)),
                      const SizedBox(height: 10),
                      _pill(
                        bg: const Color(0xFFFEE500),
                        fg: const Color(0xFF191919),
                        icon: Icons.chat_bubble_rounded,
                        label: '카카오로 로그인',
                        busy: _busy == 'kakao',
                        onTap: () => _run('kakao', AuthService.signInWithKakao),
                      ),
                      const SizedBox(height: 10),
                      _pill(
                        bg: Colors.white,
                        fg: const Color(0xFF1F1F1F),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        icon: Icons.g_mobiledata_rounded,
                        label: 'Google로 로그인',
                        busy: _busy == 'google',
                        onTap: () => _run('google', AuthService.signInWithGoogle),
                      ),
                      const SizedBox(height: 10),
                      _pill(
                        bg: const Color(0xFFF3F4F6),
                        fg: AppTheme.textPrimary,
                        icon: Icons.mail_outline_rounded,
                        label: '아이디로 로그인 / 가입',
                        busy: false,
                        onTap: () async {
                          if (!_termsOk) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('필수 약관에 모두 동의해 주세요.'),
                              ),
                            );
                            return;
                          }
                          await showEmailAuthSheet(context);
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(
                                '로그인 도움말',
                                style: GoogleFonts.notoSansKr(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              content: SingleChildScrollView(
                                child: Text(
                                  '아래를 확인해 보세요.\n\n'
                                  '• Wi-Fi 또는 모바일 데이터 연결이 안정적인지 확인해 주세요.\n'
                                  '• 잠시 후 다시 시도해 보세요.\n'
                                  '• 카카오·구글 로그인은 브라우저가 열릴 수 있습니다. '
                                  '로그인을 끝까지 완료한 뒤 앱으로 돌아와 주세요.\n'
                                  '• 위쪽에서 필수 약관에 모두 동의했는지 확인해 주세요.\n'
                                  '• 소셜 로그인이 계속 안 되면 아이디 로그인을 이용해 보세요.',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext),
                                  child: Text(
                                    '닫기',
                                    style: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text(
                          '로그인이 안 되나요?',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 시트를 완전히 내린 뒤에도 하단이 비어 보이지 않도록 스크롤 영역에 추가 카드
  Widget _buildBackgroundTipCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '앱에서 만나보세요',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _softTipCard(
                Icons.spa_outlined,
                '호흡·폐',
                '건강 루틴',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _softTipCard(
                Icons.schedule_outlined,
                '금연 시간',
                '매일 기록',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _softTipCard(
                Icons.card_giftcard_outlined,
                '보상',
                '코인·출석',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _softTipCard(
                Icons.nature_people_outlined,
                '나무 성장',
                '동기부여',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _softTipCard(IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF134E4A),
                  ),
                ),
                Text(
                  sub,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble({
    required IconData icon,
    required String text,
    required bool alignLeft,
  }) {
    final row = Row(
      mainAxisAlignment:
          alignLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        if (!alignLeft) const Spacer(),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.14),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (alignLeft) const Spacer(),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: row,
    );
  }

  Widget _termRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                value ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: value ? AppTheme.primary : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill({
    required Color bg,
    required Color fg,
    required IconData icon,
    required String label,
    required bool busy,
    required VoidCallback onTap,
    BoxBorder? border,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: border,
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        )
                      : Text(
                          label,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// 은은한 원·그라데이션으로 배경 깊이감 (터치는 통과)
class _LoginAmbientDecor extends StatelessWidget {
  const _LoginAmbientDecor();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -40,
            top: 90,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: -50,
            top: 210,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            left: -35,
            bottom: 50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.065),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 130,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.045),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.primary.withValues(alpha: 0.035),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시트를 최대한 내렸을 때 하단에 보이는 고정 문구·칩 (터치는 시트로 통과)
class _LoginBottomMotto extends StatelessWidget {
  const _LoginBottomMotto();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dot(),
            const SizedBox(width: 8),
            _dot(),
            const SizedBox(width: 8),
            _dot(),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '한 걸음씩 이어지는 금연 여정',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF134E4A).withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '출석·코인·게임으로 매일을 가볍게 기록해요',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            height: 1.45,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('출석'),
            _chip('건강'),
            _chip('코인'),
            _chip('나무'),
          ],
        ),
      ],
    );
  }

  Widget _dot() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.primary.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryDark,
        ),
      ),
    );
  }
}
