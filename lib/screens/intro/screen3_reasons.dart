// Flutter의 UI 컴포넌트 사용을 위한 패키지 import
import 'package:flutter/material.dart';

/// 사용자가 금연을 결심한 이유를 선택하는 화면
/// [onNext]는 '계속하기' 버튼을 눌렀을 때 다음 화면으로 이동하게 해주는 콜백 함수
class Screen3Reasons extends StatefulWidget {
  final VoidCallback onNext;
  const Screen3Reasons({super.key, required this.onNext});

  @override
  State<Screen3Reasons> createState() => _Screen3ReasonsState();
}

class _Screen3ReasonsState extends State<Screen3Reasons> {
  /// 사용자가 선택할 수 있는 금연 이유 목록
  final List<String> reasons = [
    '건강 회복을 위해',
    '가족을 위해',
    '경제적 절약',
    '나를 위한 자기관리',
    '습관 개선'
  ];

  /// 선택된 이유를 저장하는 변수
  String? selectedReason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 전체 배경 흰색 설정

      body: Padding(
        padding: const EdgeInsets.all(24), // 전체 콘텐츠 여백

        // 콘텐츠를 세로로 나열
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // 좌측 정렬
          mainAxisAlignment: MainAxisAlignment.center, // 수직 중앙 정렬
          children: [
            // 제목 텍스트
            const Text(
              '금연을 결심한 이유는 무엇인가요?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24), // 제목과 라디오 버튼 사이 간격

            // 금연 이유 리스트를 라디오 버튼 형태로 출력
            ...reasons.map((reason) => RadioListTile<String>(
              title: Text(reason, style: const TextStyle(fontSize: 18)), // 이유 텍스트
              value: reason, // 현재 항목의 값
              groupValue: selectedReason, // 선택된 항목과 비교
              onChanged: (value) => setState(() => selectedReason = value), // 선택되면 상태 갱신
            )),

            const SizedBox(height: 40), // 버튼과 항목들 사이 간격

            // '계속하기' 버튼 (선택된 이유가 있을 때만 활성화됨)
            Center(
              child: ElevatedButton(
                onPressed: selectedReason != null ? widget.onNext : null, // 이유 선택 안 했으면 비활성화
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, // 버튼 배경색
                  foregroundColor: Colors.white, // 버튼 글자색
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                ),
                child: const Text(
                  '계속하기',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}