import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

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
    _controller.repeat();
  }

  void _onPressEnd() {
    setState(() => _isSmoking = false);
    _controller.stop();
    _controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F9),
      appBar: AppBar(
        elevation: 2,
        backgroundColor: Colors.brown.shade600,
        centerTitle: true,
        title: const Text(
          "흡연 시뮬레이션 🚬",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 🔸 설명 텍스트 카드
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  children: [
                    Text(
                      _isSmoking
                          ? "연기가 피어오르고 있습니다 ☁️"
                          : "버튼을 누르면 흡연 애니메이션이 재생됩니다.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: _isSmoking
                            ? Colors.redAccent
                            : Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSmoking
                          ? "흡연 중... 건강을 위해 잠시 멈춰보세요 🚫"
                          : "이 장면은 흡연의 습관적 행동을 보여줍니다.",
                      textAlign: TextAlign.center,
                      style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
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
                        color: Colors.grey.withOpacity(0.15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 메인 Lottie 애니메이션
                  Lottie.asset(
                    'assets/lottie/Cig.json',
                    controller: _controller,
                    onLoaded: (composition) {
                      _controller.duration = composition.duration;
                    },
                    repeat: true,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),

            // 🚬 버튼
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
                        ? [Colors.redAccent.shade200, Colors.red.shade700]
                        : [Colors.brown.shade500, Colors.brown.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: _isSmoking
                          ? Colors.redAccent.withOpacity(0.4)
                          : Colors.brown.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  _isSmoking ? "흡연 중..." : "담배 피우기 시작",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // 하단 문구
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _isSmoking
                    ? "잠깐의 흡연, 오랜 회복이 필요합니다 💨"
                    : "흡연을 줄이면 폐가 점차 회복됩니다 🌿",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isSmoking ? Colors.redAccent : Colors.grey.shade700,
                  fontSize: 14,
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