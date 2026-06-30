import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        size: 120,
        color: Colors.grey.shade600,
      );
    }
    return const Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('담타시간(커뮤니티)'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            24,
            20,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    Text(
                      _isBurning
                          ? '담배가 자동으로 타는 중이에요'
                          : '버튼을 누르면 담타가 시작됩니다.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyLarge.copyWith(
                        color:
                            _isBurning ? AppTheme.error : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '담배 이미지를 누르면 더 빨리 탑니다.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _burnProgress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor:
                          AppTheme.textMuted.withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isFastBurn ? AppTheme.warning : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isBurning
                          ? '남은 시간 ${(_remainingSeconds ~/ 60).toInt()}분 ${(_remainingSeconds % 60).toInt().toString().padLeft(2, '0')}초'
                          : '남은 시간 5분 00초',
                      style: AppTheme.labelMedium
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 300,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: _isBurning ? 1 : 0,
                      duration: const Duration(milliseconds: 600),
                      child: Container(
                        height: 240,
                        width: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.withValues(alpha: 0.15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.3),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
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
                      child: _buildCigaretteVisual(),
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
                                duration: const Duration(milliseconds: 1200),
                                curve: Curves.easeOut,
                                opacity: chat.visible ? 1 : 0,
                                child: Transform.translate(
                                  offset: Offset(
                                    chat.dx,
                                    chat.visible ? chat.dy : chat.dy - 12,
                                  ),
                                  child: Text(
                                    chat.renderedText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: chat.color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.white,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_isBurning)
                      Positioned(
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (_isFastBurn
                                    ? AppTheme.warning
                                    : AppTheme.primary)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _isFastBurn ? '2배속 ON (누르는 중)' : '누르고 있으면 2배속',
                            style: AppTheme.labelMedium.copyWith(
                              color: _isFastBurn
                                  ? AppTheme.warning
                                  : AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isBurning ? null : _onTapStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isBurning ? AppTheme.textMuted : AppTheme.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _isBurning ? '담타 진행 중...' : '담타 시작',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppTheme.cardShadowSubtle,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        focusNode: _chatFocusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendEphemeralChat(),
                        decoration: const InputDecoration(
                          hintText: '한마디 입력...',
                          border: InputBorder.none,
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
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  ApiConfig.isConfigured
                      ? '지금 동시 접속자수 : ${_damtaPresenceCount ?? '-'}명'
                      : '지금 동시 접속자수 : -명',
                  textAlign: TextAlign.center,
                  style: AppTheme.labelMedium.copyWith(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              if (ApiConfig.isConfigured)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '매주 일요일 밤 24:00에 올린 글은 초기화됩니다.',
                    textAlign: TextAlign.center,
                    style: AppTheme.labelMedium.copyWith(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _isBurning
                      ? '한순간의 선택이 회복 시간을 늘립니다.'
                      : '중요한 건 완벽이 아니라 다시 복귀하는 습관입니다.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium.copyWith(
                    color: _isBurning ? AppTheme.error : AppTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
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
