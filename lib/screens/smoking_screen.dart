import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'dart:math';
import '../api/api_config.dart';
import '../api/bff_profile_api.dart';
import '../api/damta_community_api_service.dart';
import '../api/remote_assets.dart';
import '../theme/app_theme.dart';
import '../utils/profanity_filter.dart';

class SmokingScreen extends StatefulWidget {
  const SmokingScreen({super.key});

  @override
  State<SmokingScreen> createState() => _SmokingScreenState();
}

class _SmokingScreenState extends State<SmokingScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _lottieController;
  Timer? _burnTimer;
  Timer? _holdHapticTimer;
  Timer? _damtaPollTimer;
  bool _damtaPollInFlight = false;
  bool _isBurning = false;
  bool _isFastBurn = false;
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final List<_EphemeralChat> _serverDamtaChats = [];
  final List<_EphemeralChat> _localDamtaChats = [];
  final Random _random = Random();
  static const DamtaCommunityApiService _damtaApi = DamtaCommunityApiService();
  String _myDisplayName = '나';
  LottieComposition? _cigComposition;
  bool _cigLoadFailed = false;
  static const List<Alignment> _chatAnchors = [
    Alignment(-0.9, -0.82),
    Alignment(-0.35, -0.92),
    Alignment(0.25, -0.92),
    Alignment(0.85, -0.82),
    Alignment(-0.98, -0.35),
    Alignment(0.98, -0.35),
    Alignment(-0.95, 0.15),
    Alignment(0.95, 0.15),
  ];
  static const int _burnSecondsPerCigarette = 300;
  double _remainingSeconds = _burnSecondsPerCigarette.toDouble();
  double _burnProgress = 0;
  int? _damtaPresenceCount;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMyDisplayName());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadCigLottie());
      if (!ApiConfig.isConfigured) return;
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        _damtaPollTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => unawaited(_pollDamtaInbox()),
        );
        unawaited(_pollDamtaInbox());
      });
    });
  }

  Future<void> _loadCigLottie() async {
    if (!ApiConfig.isConfigured) return;
    try {
      final url = RemoteAssets.urlForKey('lottie/Cig.json');
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw StateError('lottie http ${res.statusCode}');
      }
      final composition = await LottieComposition.fromBytes(res.bodyBytes);
      if (!mounted) return;
      final controller = AnimationController(
        vsync: this,
        duration: composition.duration,
        lowerBound: 0,
        upperBound: 1,
      );
      setState(() {
        _cigComposition = composition;
        _lottieController = controller;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cigLoadFailed = true);
    }
  }

  Future<void> _loadMyDisplayName() async {
    final cached = await BffProfileApi.readCachedDisplayNameForCurrentUser();
    if (!mounted) return;
    if (cached != null && cached.trim().isNotEmpty) {
      setState(() => _myDisplayName = cached.trim());
      return;
    }
    final row = await BffProfileApi.fetchProfile();
    if (!mounted || row == null) return;
    final fromServer = (row['display_name'] as String?)?.trim();
    if (fromServer != null && fromServer.isNotEmpty) {
      await BffProfileApi.cacheDisplayNameForCurrentUser(fromServer);
      if (mounted) setState(() => _myDisplayName = fromServer);
    }
  }

  @override
  void dispose() {
    _damtaPollTimer?.cancel();
    _burnTimer?.cancel();
    _holdHapticTimer?.cancel();
    _chatController.dispose();
    _chatFocusNode.dispose();
    _lottieController?.dispose();
    super.dispose();
  }

  void _onTapStart() {
    if (_isBurning) return;
    setState(() {
      _isBurning = true;
      _isFastBurn = false;
      _remainingSeconds = _burnSecondsPerCigarette.toDouble();
      _burnProgress = 0;
      _lottieController?.value = 0;
    });
    _startBurningTimer();
  }

  void _startBurningTimer() {
    _burnTimer?.cancel();
    _burnTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isBurning) {
        timer.cancel();
        return;
      }

      final speed = _isFastBurn ? 2.0 : 1.0;
      final deltaSeconds = 0.1 * speed;
      final nextRemaining = (_remainingSeconds - deltaSeconds)
          .clamp(0.0, _burnSecondsPerCigarette.toDouble());
      final progress = ((_burnSecondsPerCigarette - nextRemaining) /
              _burnSecondsPerCigarette)
          .clamp(0.0, 1.0);

      setState(() {
        _remainingSeconds = nextRemaining;
        _burnProgress = progress;
        _lottieController?.value = progress;
      });

      if (nextRemaining <= 0) {
        timer.cancel();
        _stopHoldHaptic();
        setState(() {
          _isBurning = false;
          _isFastBurn = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('한 대가 모두 탔어요. 잠깐 멈추고 물 한 잔 해보세요.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  void _setFastBurnPressed(bool pressed) {
    if (!_isBurning) return;
    if (_isFastBurn == pressed) return;
    setState(() => _isFastBurn = pressed);
  }

  void _vibratePress() => HapticFeedback.heavyImpact();

  void _vibrateHoldTick() => HapticFeedback.selectionClick();

  void _startHoldHaptic() {
    _holdHapticTimer?.cancel();
    _vibratePress();
    _holdHapticTimer = Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (!mounted || !_isBurning || !_isFastBurn) {
        _stopHoldHaptic();
        return;
      }
      _vibrateHoldTick();
    });
  }

  void _stopHoldHaptic() {
    _holdHapticTimer?.cancel();
    _holdHapticTimer = null;
  }

  Future<void> _pollDamtaInbox() async {
    if (_damtaPollInFlight) return;
    _damtaPollInFlight = true;
    try {
      final list = await _damtaApi.fetchMessages();
      final presence = await _damtaApi.postPresence();
      if (!mounted) return;
      setState(() {
        if (presence != null) {
          _damtaPresenceCount = presence;
        }
        if (list != null) {
          final sorted = [...list]..sort((a, b) => a.tsMs.compareTo(b.tsMs));
          _serverDamtaChats
            ..clear()
            ..addAll(sorted.map(_chatBubbleFromMessage));
        }
      });
    } finally {
      _damtaPollInFlight = false;
    }
  }

  _EphemeralChat _chatBubbleFromMessage(DamtaCommunityMessage m) {
    final h = Object.hash(m.id, m.tsMs);
    final anchorIndex = h.abs() % _chatAnchors.length;
    final dx = ((h >> 3) % 200) / 10.0 - 10;
    final dy = ((h >> 7) % 160) / 10.0 - 8;
    return _EphemeralChat(
      id: m.id,
      text: m.text,
      color: m.color,
      authorName: m.authorName,
      anchorIndex: anchorIndex,
      dx: dx,
      dy: dy,
      visible: true,
    );
  }

  void _enqueueLocalEphemeralBubble({
    required String id,
    required String text,
    required Color color,
    required String authorName,
  }) {
    final dx = (_random.nextDouble() * 20) - 10;
    final dy = (_random.nextDouble() * 16) - 8;
    final anchorIndex = _pickLeastUsedAnchorIndex();
    final chat = _EphemeralChat(
      id: id,
      text: text,
      color: color,
      authorName: authorName,
      anchorIndex: anchorIndex,
      dx: dx,
      dy: dy,
      visible: true,
    );
    setState(() => _localDamtaChats.add(chat));

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      final idx = _localDamtaChats.indexWhere((c) => c.id == id);
      if (idx < 0) return;
      setState(
        () => _localDamtaChats[idx] =
            _localDamtaChats[idx].copyWith(visible: false),
      );
    });
    Future.delayed(const Duration(milliseconds: 4300), () {
      if (!mounted) return;
      setState(() => _localDamtaChats.removeWhere((c) => c.id == id));
    });
  }

  Future<void> _sendEphemeralChat() async {
    final raw = _chatController.text.trim();
    if (raw.isEmpty) return;
    final text = ProfanityFilter.sanitize(raw).trim();
    if (text.isEmpty) return;
    _chatController.clear();
    _chatFocusNode.unfocus();

    final color = Color.lerp(
          const Color(0xFF22D3EE),
          const Color(0xFFF472B6),
          _random.nextDouble(),
        ) ??
        AppTheme.primary;

    if (ApiConfig.isConfigured) {
      final result = await _damtaApi.postMessageDetailed(
        text: text,
        color: color,
        authorName: _myDisplayName,
      );
      if (!mounted) return;
      if (result.message == null) {
        final msg = switch (result.failure) {
          DamtaPostFailure.notLoggedIn => '한마디를 남기려면 로그인이 필요해요.',
          DamtaPostFailure.rateLimited => '잠시 후 다시 시도해 주세요.',
          DamtaPostFailure.emptyAfterFilter =>
            '보낼 수 없는 내용이에요. 다른 표현으로 입력해 주세요.',
          DamtaPostFailure.serviceUnavailable =>
            '서버 설정 문제로 한마디를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.',
          DamtaPostFailure.notConfigured ||
          DamtaPostFailure.serverError ||
          null =>
            '한마디를 보내지 못했어요. 네트워크를 확인해 주세요.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      }
      unawaited(_pollDamtaInbox());
      return;
    }

    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    _enqueueLocalEphemeralBubble(
      id: id,
      text: text,
      color: color,
      authorName: '나',
    );
  }

  int _pickLeastUsedAnchorIndex() {
    final counts = List<int>.filled(_chatAnchors.length, 0);
    for (final chat in [..._serverDamtaChats, ..._localDamtaChats]) {
      if (!chat.visible) continue;
      if (chat.anchorIndex >= 0 && chat.anchorIndex < counts.length) {
        counts[chat.anchorIndex] += 1;
      }
    }
    final minCount = counts.reduce((a, b) => a < b ? a : b);
    final candidates = <int>[];
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == minCount) {
        candidates.add(i);
      }
    }
    return candidates[_random.nextInt(candidates.length)];
  }

  Widget _buildCigaretteVisual() {
    final composition = _cigComposition;
    final controller = _lottieController;
    if (composition != null && controller != null) {
      return Lottie(
        composition: composition,
        controller: controller,
        repeat: false,
        fit: BoxFit.contain,
      );
    }
    if (_cigLoadFailed || !ApiConfig.isConfigured) {
      return Icon(
        Icons.smoking_rooms_rounded,
        size: 100,
        color: Colors.white.withValues(alpha: 0.55),
      );
    }
    return const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Colors.white70,
        ),
      ),
    );
  }

  String get _remainingLabel {
    final m = (_remainingSeconds ~/ 60).toInt();
    final s = (_remainingSeconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final presence = _damtaPresenceCount;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('담타시간'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A3D38),
              Color(0xFF0F524A),
              Color(0xFF1A3A36),
              Color(0xFF152826),
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
            child: Column(
              children: [
                // 함께하는 사람들
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: presence != null && presence > 0
                              ? const Color(0xFF6EE7B7)
                              : Colors.white38,
                          shape: BoxShape.circle,
                          boxShadow: presence != null && presence > 0
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF6EE7B7)
                                        .withValues(alpha: 0.55),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        ApiConfig.isConfigured
                            ? '지금 ${presence ?? '—'}명이 함께 있어요'
                            : '조용한 밤, 혼자도 괜찮아요',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // 시적인 헤드라인
                Text(
                  _isBurning ? '천천히, 태워내세요' : '욕구가 올 때\n여기서 잠깐 쉬어가요',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: _isBurning ? 22 : 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.35,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isBurning
                      ? '담배 이미지를 길게 누르면 더 빨리 탑니다'
                      : '한 대를 태우는 동안, 한마디를 남겨 보세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),

                // 담배 + 플로팅 채팅
                SizedBox(
                  height: 280,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 은은한 원형 글로우
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 800),
                        height: _isBurning ? 220 : 180,
                        width: _isBurning ? 220 : 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              (_isBurning
                                      ? (_isFastBurn
                                          ? const Color(0xFFE8A54B)
                                          : const Color(0xFF2DD4A8))
                                      : const Color(0xFF1A6B5E))
                                  .withValues(alpha: _isBurning ? 0.28 : 0.14),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) {
                          if (!_isBurning) return;
                          _setFastBurnPressed(true);
                          _startHoldHaptic();
                        },
                        onPointerUp: (_) {
                          _setFastBurnPressed(false);
                          _stopHoldHaptic();
                        },
                        onPointerCancel: (_) {
                          _setFastBurnPressed(false);
                          _stopHoldHaptic();
                        },
                        child: SizedBox(
                          height: 160,
                          width: double.infinity,
                          child: _buildCigaretteVisual(),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: true,
                        child: Stack(
                          children: [
                            for (final chat
                                in [..._serverDamtaChats, ..._localDamtaChats])
                              Align(
                                alignment: _chatAnchors[chat.anchorIndex],
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 900),
                                  curve: Curves.easeOut,
                                  opacity: chat.visible ? 1 : 0,
                                  child: Transform.translate(
                                    offset: Offset(
                                      chat.dx,
                                      chat.visible ? chat.dy : chat.dy - 14,
                                    ),
                                    child: _FloatingWhisper(chat: chat),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_isBurning)
                        Positioned(
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              _isFastBurn ? '2배속으로 타는 중' : '길게 누르면 2배속',
                              style: TextStyle(
                                color: _isFastBurn
                                    ? const Color(0xFFFBBF24)
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 진행률
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _isBurning ? _burnProgress : 0,
                          minHeight: 6,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _isFastBurn
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF5EEAD4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isBurning ? '남은 시간  $_remainingLabel' : '한 대 · 5:00',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // 시작 버튼
                SizedBox(
                  width: double.infinity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    child: FilledButton(
                      onPressed: _isBurning ? null : _onTapStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: _isBurning
                            ? Colors.white12
                            : const Color(0xFFE8A54B),
                        foregroundColor: _isBurning
                            ? Colors.white54
                            : const Color(0xFF1A2421),
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _isBurning ? '담타 진행 중…' : '담타 시작하기',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 한마디 입력
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          focusNode: _chatFocusNode,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendEphemeralChat(),
                          style: const TextStyle(
                            color: Color(0xFF1A2421),
                            fontSize: 15,
                          ),
                          cursorColor: AppTheme.primary,
                          decoration: InputDecoration(
                            hintText: '한마디를 남겨요…',
                            hintStyle: TextStyle(
                              color: AppTheme.textMuted.withValues(alpha: 0.8),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _sendEphemeralChat,
                        icon: const Icon(Icons.send_rounded),
                        tooltip: '보내기',
                        color: AppTheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 풋터 카피
                Text(
                  _isBurning
                      ? '한순간의 선택이 회복을 늦춥니다.\n여기는 그 순간을 넘기는 자리예요.'
                      : '완벽하지 않아도 괜찮아요.\n다시 돌아오는 습관이 곧 금연입니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                    height: 1.55,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (ApiConfig.isConfigured) ...[
                  const SizedBox(height: 12),
                  Text(
                    '올린 한마디는 매주 일요일 밤 24:00에 비워져요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingWhisper extends StatelessWidget {
  const _FloatingWhisper({required this.chat});

  final _EphemeralChat chat;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: chat.color.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        chat.renderedText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chat.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}

class _EphemeralChat {
  final String id;
  final String text;
  final Color color;
  final String authorName;
  final int anchorIndex;
  final double dx;
  final double dy;
  final bool visible;

  const _EphemeralChat({
    required this.id,
    required this.text,
    required this.color,
    required this.authorName,
    required this.anchorIndex,
    required this.dx,
    required this.dy,
    required this.visible,
  });

  _EphemeralChat copyWith({
    bool? visible,
  }) {
    return _EphemeralChat(
      id: id,
      text: text,
      color: color,
      authorName: authorName,
      anchorIndex: anchorIndex,
      dx: dx,
      dy: dy,
      visible: visible ?? this.visible,
    );
  }

  String get renderedText {
    final name = authorName.trim();
    if (name.isEmpty) return text;
    return '($name) $text';
  }
}
