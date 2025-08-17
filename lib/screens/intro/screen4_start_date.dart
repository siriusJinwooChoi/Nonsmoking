// Flutter의 UI 요소 사용을 위한 필수 패키지
import 'package:flutter/material.dart';

/// 금연 시작일을 설정하는 화면
/// [onNext]는 '계속하기' 버튼 클릭 시 다음 화면으로 이동하는 콜백 함수
class Screen4StartDate extends StatefulWidget {
  final VoidCallback onNext;

  const Screen4StartDate({super.key, required this.onNext});

  @override
  State<Screen4StartDate> createState() => _Screen4StartDateState();
}

class _Screen4StartDateState extends State<Screen4StartDate> {
  // 사용자가 선택한 날짜를 저장할 변수 (초기에는 null)
  DateTime? selectedDate;

  /// 날짜 선택 다이얼로그를 띄우고 선택된 날짜를 저장
  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now(); // 현재 날짜 기준
    final picked = await showDatePicker(
      context: context,
      initialDate: now, // 기본값: 오늘 날짜
      firstDate: DateTime(now.year - 5), // 과거 5년까지 선택 가능
      lastDate: now, // 오늘 이전까지만 선택 가능
    );

    // 사용자가 날짜를 선택한 경우만 처리
    if (picked != null) {
      setState(() {
        selectedDate = picked; // 선택된 날짜 저장
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('금연 시작일 설정'),
      ),
      backgroundColor: Colors.white,

      // 전체 화면 패딩 적용
      body: Padding(
        padding: const EdgeInsets.all(24),

        // 화면 중앙에 세로 정렬된 콘텐츠
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 안내 문구
            const Text(
              '금연을 시작한 날짜를 선택해주세요',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // 날짜 선택 버튼
            ElevatedButton(
              onPressed: () => _pickDate(context),
              child: const Text('날짜 선택'),
            ),

            const SizedBox(height: 20),

            // 날짜를 선택한 경우에만 출력되는 텍스트
            if (selectedDate != null)
              Text(
                '선택한 날짜: ${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 18),
              ),

            const SizedBox(height: 40),

            // 계속하기 버튼 (날짜를 선택하지 않았을 경우 비활성화됨)
            ElevatedButton(
              onPressed: selectedDate != null ? widget.onNext : null,
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