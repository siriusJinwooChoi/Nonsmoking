import 'package:flutter/material.dart';

/// 담배 1갑의 가격을 입력받는 화면입니다.
/// 사용자가 입력한 가격은 onNext 콜백을 통해 다음 화면으로 전달됩니다.
class Screen8Price extends StatefulWidget {
  final Function(int) onNext;

  // 필수 콜백 인자를 받는 생성자
  const Screen8Price({super.key, required this.onNext});

  @override
  State<Screen8Price> createState() => _Screen8PriceState();
}

class _Screen8PriceState extends State<Screen8Price> {
  // 사용자 입력을 받기 위한 텍스트 컨트롤러
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    // 화면이 dispose될 때 컨트롤러도 함께 해제
    _controller.dispose();
    super.dispose();
  }

  /// 입력값을 검증하고 유효한 경우 onNext 콜백 호출
  void _handleNext() {
    final price = int.tryParse(_controller.text); // 입력값을 정수로 변환
    if (price != null && price > 0) {
      widget.onNext(price); // 다음 화면으로 전달
    } else {
      // 유효하지 않은 입력일 경우 경고 메시지 출력
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격을 숫자로 정확히 입력해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 앱 상단의 AppBar 구성
      appBar: AppBar(
        title: const Text('담배 1갑 가격 입력'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()), // 뒤로가기 버튼
      ),
      // 본문 내용 구성
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 텍스트
            const Text('담배 1갑의 가격을 입력해주세요.', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 20),

            // 숫자 입력 필드
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number, // 숫자 키보드 표시
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '가격 (₩)', // 입력 필드에 표시되는 라벨
              ),
            ),
            const SizedBox(height: 20),

            // 계속하기 버튼 (입력값이 유효할 경우 다음 화면으로 이동)
            Center(
              child: ElevatedButton(
                onPressed: _handleNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, // 배경색
                  foregroundColor: Colors.white, // 글자색
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
                child: const Text('계속하기', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}