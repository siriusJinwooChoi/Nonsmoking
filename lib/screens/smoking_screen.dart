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
    // Lottie 애니메이션 컨트롤러 초기화
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPressStart() {
    setState(() => _isSmoking = true);
    _controller.repeat(); // 누르는 동안 계속 연기 재생
  }

  void _onPressEnd() {
    setState(() => _isSmoking = false);
    _controller.stop();
    _controller.reset(); // 손을 떼면 다시 초기화
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("흡연하기"),
        backgroundColor: Colors.grey.shade800,
      ),
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "🚬 담배 피우기",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 200,
              width: 300,
              child: Lottie.asset(
                'assets/lottie/Cig.json', // ✅ 담배 애니메이션 JSON 경로
                controller: _controller,
                onLoaded: (composition) {
                  _controller.duration = composition.duration;
                },
                repeat: true,
              ),
            ),
            const SizedBox(height: 50),
            GestureDetector(
              onTapDown: (_) => _onPressStart(), // 버튼 누를 때
              onTapUp: (_) => _onPressEnd(), // 손 뗄 때
              onTapCancel: _onPressEnd, // 손가락 벗어날 때
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                decoration: BoxDecoration(
                  color: _isSmoking ? Colors.redAccent : Colors.brown,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _isSmoking ? "흡연 중..." : "담배 피우기",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              _isSmoking
                  ? "연기가 피어오르는 중..."
                  : "버튼을 누르면 담배를 피웁니다.",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}