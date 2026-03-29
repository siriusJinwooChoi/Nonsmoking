import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../api/api_config.dart';
import '../api/remote_assets.dart';
import '../theme/app_theme.dart';

class SmokingScreen extends StatefulWidget {
  const SmokingScreen({super.key});

  @override
  State<SmokingScreen> createState() => _SmokingScreenState();
}

class _SmokingScreenState extends State<SmokingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSmoking = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPressStart() {
    setState(() => _isSmoking = true);
    if (ApiConfig.isConfigured) {
      _controller.repeat();
    }
  }

  void _onPressEnd() {
    setState(() => _isSmoking = false);
    if (ApiConfig.isConfigured) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('금연해보도록 노력해봐요'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                children: [
                  Text(
                    _isSmoking
                        ? '장면이 재생 중이에요'
                        : '버튼을 누르면 연습 장면이 재생됩니다.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyLarge.copyWith(
                      color: _isSmoking ? AppTheme.error : AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSmoking
                        ? '재생 중… 잠깐 손을 떼며 숨을 고르세요.'
                        : '잠깐의 유혹이 몸에 어떤 느낌인지 떠올려 보는 연습입니다.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            // 🌀 Lottie 애니메이션
            SizedBox(
              height: 250,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 배경 효과 (연기처럼 흐릿한 원)
                  AnimatedOpacity(
                    opacity: _isSmoking ? 1 : 0,
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

                  // 메인 Lottie 애니메이션 (서버 static)
                  if (ApiConfig.isConfigured)
                    Lottie.network(
                      RemoteAssets.urlForKey('lottie/Cig.json').toString(),
                      controller: _controller,
                      onLoaded: (composition) {
                        _controller.duration = composition.duration;
                      },
                      repeat: true,
                      fit: BoxFit.contain,
                    )
                  else
                    Icon(Icons.movie_filter_rounded, size: 120, color: Colors.grey.shade600),
                ],
              ),
            ),

            // 연습 재생 버튼
            GestureDetector(
              onTapDown: (_) => _onPressStart(),
              onTapUp: (_) => _onPressEnd(),
              onTapCancel: _onPressEnd,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding:
                const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isSmoking
                        ? [const Color(0xFFF87171), AppTheme.error]
                        : [const Color(0xFF78716C), const Color(0xFF57534E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (_isSmoking ? AppTheme.error : const Color(0xFF57534E)).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _isSmoking ? '기록 중...' : '흔들림 기록 시작',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // 하단 문구
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _isSmoking
                    ? '한순간의 선택이 회복 시간을 늘립니다.'
                    : '유혹을 넘길수록 폐는 천천히 회복됩니다.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyMedium.copyWith(
                  color: _isSmoking ? AppTheme.error : AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}