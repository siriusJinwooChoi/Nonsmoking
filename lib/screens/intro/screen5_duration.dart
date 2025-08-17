// Flutter UI 위젯 패키지
import 'package:flutter/material.dart';

/// 금연 앱의 5번째 화면: 사용자의 흡연 기간(년/월/일)을 입력받는 화면
class Screen5Duration extends StatefulWidget {
  // 선택된 총 흡연 일수를 다음 단계로 전달하는 콜백 함수
  final Function(int) onNext;

  const Screen5Duration({super.key, required this.onNext});

  @override
  State<Screen5Duration> createState() => _Screen5DurationState();
}

class _Screen5DurationState extends State<Screen5Duration> {
  // 사용자가 선택한 흡연 기간 (년/월/일)
  int years = 0;
  int months = 0;
  int days = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 AppBar 설정
      appBar: AppBar(
        title: const Text('흡연 기간 입력'),
      ),

      backgroundColor: Colors.white,

      // 화면 전체에 패딩 적용
      body: Padding(
        padding: const EdgeInsets.all(24),

        // 화면 중앙 정렬된 세로 레이아웃
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 제목 텍스트
            const Text(
              '흡연을 얼마나 오래 하셨나요?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // 년, 월, 일 선택 드롭다운을 나란히 배치
            Row(
              children: [
                // 년 선택 드롭다운
                Expanded(
                  child: Column(
                    children: [
                      const Text('년', style: TextStyle(fontSize: 18)),
                      DropdownButton<int>(
                        value: years,
                        items: List.generate(
                          51, // 0~50년 선택 가능
                              (i) => DropdownMenuItem(value: i, child: Text('$i')),
                        ),
                        onChanged: (val) => setState(() => years = val!),
                      ),
                    ],
                  ),
                ),

                // 월 선택 드롭다운
                Expanded(
                  child: Column(
                    children: [
                      const Text('월', style: TextStyle(fontSize: 18)),
                      DropdownButton<int>(
                        value: months,
                        items: List.generate(
                          12, // 0~11월 선택 가능
                              (i) => DropdownMenuItem(value: i, child: Text('$i')),
                        ),
                        onChanged: (val) => setState(() => months = val!),
                      ),
                    ],
                  ),
                ),

                // 일 선택 드롭다운
                Expanded(
                  child: Column(
                    children: [
                      const Text('일', style: TextStyle(fontSize: 18)),
                      DropdownButton<int>(
                        value: days,
                        items: List.generate(
                          31, // 0~30일 선택 가능
                              (i) => DropdownMenuItem(value: i, child: Text('$i')),
                        ),
                        onChanged: (val) => setState(() => days = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // 계속하기 버튼
            ElevatedButton(
              onPressed: () {
                // 총 흡연 일수 계산: 1년=365일, 1월=30일로 간주
                final totalDays = years * 365 + months * 30 + days;

                // 부모 위젯에 결과 전달
                widget.onNext(totalDays);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: const Text('계속하기', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}