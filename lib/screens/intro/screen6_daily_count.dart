// Flutter의 기본 UI 컴포넌트 패키지
import 'package:flutter/material.dart';

/// 금연 앱의 6번째 화면: 하루 흡연량(개비 수)을 숫자로 입력 받는 페이지
class Screen6DailyCount extends StatefulWidget {
  // 입력된 개비 수를 부모 위젯으로 전달하는 콜백 함수
  final Function(int) onNext;

  const Screen6DailyCount({super.key, required this.onNext});

  @override
  State<Screen6DailyCount> createState() => _Screen6DailyCountState();
}

class _Screen6DailyCountState extends State<Screen6DailyCount> {
  // 텍스트 필드 입력값을 관리하기 위한 컨트롤러
  final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    // 컨트롤러 메모리 해제
    controller.dispose();
    super.dispose();
  }

  /// 계속하기 버튼을 눌렀을 때 호출되는 로직
  void handleNext() {
    // 입력값을 정수형으로 파싱 시도
    final cigarettes = int.tryParse(controller.text);

    if (cigarettes != null) {
      // 유효한 숫자일 경우 다음 단계로 값 전달
      widget.onNext(cigarettes);
    } else {
      // 숫자가 아닐 경우 사용자에게 알림 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('숫자를 정확히 입력해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 제목 표시
      appBar: AppBar(title: const Text('하루 흡연량 입력')),

      // 화면 전체에 패딩 적용
      body: Padding(
        padding: const EdgeInsets.all(24),

        // 수직 레이아웃 구성
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 문구
            const Text(
              '하루에 피우는 담배 개비 수를 입력해주세요.',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),

            // 숫자 입력 필드
            TextField(
              controller: controller,
              keyboardType: TextInputType.number, // 숫자 키패드 제공
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '개비 수',
              ),
            ),
            const SizedBox(height: 20),

            // 계속하기 버튼
            ElevatedButton(
              onPressed: handleNext,
              child: const Text('계속하기'),
            ),
          ],
        ),
      ),
    );
  }
}