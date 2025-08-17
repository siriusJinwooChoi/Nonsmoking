// Flutter UI 구성 요소를 불러옵니다.
import 'package:flutter/material.dart';
// 다음 단계 화면(Screen8)을 불러오는 코드 (현재는 사용되지 않지만 나중에 확장 가능)
import 'screen8_price.dart';

/// 금연 앱의 7번째 화면
/// 사용자에게 '한 갑에 담배가 몇 개비 들어있는지' 숫자를 입력받음
class Screen7PerPack extends StatefulWidget {
  // 값을 전달받기 위한 콜백 함수
  final Function(int) onNext;

  const Screen7PerPack({super.key, required this.onNext});

  @override
  State<Screen7PerPack> createState() => _Screen7PerPackState();
}

class _Screen7PerPackState extends State<Screen7PerPack> {
  // 텍스트 필드에 입력되는 값을 제어하기 위한 컨트롤러
  final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    // 메모리 누수를 방지하기 위해 컨트롤러 해제
    controller.dispose();
    super.dispose();
  }

  /// '계속하기' 버튼을 눌렀을 때 호출되는 로직
  /// 입력값을 정수로 변환하고 유효성 검사
  void handleNext() {
    final cigarettes_pack = int.tryParse(controller.text);

    if (cigarettes_pack != null) {
      // 유효한 숫자일 경우 콜백 함수를 호출하여 다음 화면으로 전달
      widget.onNext(cigarettes_pack);
    } else {
      // 입력값이 숫자가 아닐 경우 오류 메시지 출력
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정확한 숫자를 입력해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 앱 바 제목
      appBar: AppBar(title: const Text('한 갑의 담배 개비 수')),

      // 본문 레이아웃
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 안내 텍스트
            const Text(
              '한 갑에 들어있는 담배 개비 수를 입력해주세요.',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),

            // 사용자 입력 필드
            TextField(
              controller: controller,
              keyboardType: TextInputType.number, // 숫자 키패드 활성화
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '개비 수',
              ),
            ),
            const SizedBox(height: 20),

            // 계속하기 버튼
            ElevatedButton(
              onPressed: handleNext, // 눌렀을 때 처리 로직 호출
              child: const Text('계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}