// Flutter UI 생성을 위한 기본 Material 패키지 import
import 'package:flutter/material.dart';

/// 금연의 장점을 소개하는 두 번째 인트로 화면 클래스
class Screen2Goals extends StatelessWidget {
  final VoidCallback onNext; // '계속하기' 버튼 클릭 시 호출될 콜백 함수

  // 필수 파라미터인 onNext를 생성자에서 전달받음
  const Screen2Goals({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    // 금연을 통해 얻을 수 있는 혜택들을 문자열 리스트로 정의
    final List<String> goals = [
      '✔ 건강 증진 및 질병 예방: 흡연은 폐암, 심근경색, 뇌졸중, 만성폐쇄성폐질환(COPD) 등 각종 질병의 주요 원인입니다.',
      '✔ 수명 연장: 금연을 통해 심장 질환과 암의 발생률이 낮아지고, 폐 기능이 회복되며, 조기 사망 위험이 감소합니다.',
      '✔ 가족과 타인의 건강 보호: 간접흡연 역시 폐암, 천식, 심혈관 질환을 유발합니다. 금연은 가족, 특히 어린이와 임산부의 건강을 보호하는 중요한 실천입니다.',
      '✔ 경제적 부담 감소: 담배 구입에 드는 직접 비용뿐만 아니라 흡연으로 인한 질병 치료 비용도 절감할 수 있습니다.',
      '✔ 자기 통제력 강화 및 자존감 향상: 금연은 자기 자신에 대한 통제력을 회복하는 과정이며, 심리적으로 안정되고 자존감도 높아지는 긍정적 효과가 있습니다.'
    ];

    return Scaffold(
      backgroundColor: Colors.white, // 전체 배경은 흰색

      // 콘텐츠 여백 설정
      body: Padding(
        padding: const EdgeInsets.all(24),

        // 콘텐츠 구성: 텍스트와 버튼을 세로로 정렬
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // 세로 중앙 정렬
          crossAxisAlignment: CrossAxisAlignment.start, // 좌측 정렬

          children: [
            // 제목 텍스트
            const Text(
              '금연을 통해 얻을 수 있는 것들',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 24), // 제목과 리스트 사이 간격

            // 금연 효과 리스트를 화면에 반복 출력
            ...goals.map((goal) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4), // 각 항목 간 간격
              child: Text(
                goal,
                style: const TextStyle(fontSize: 15),
              ),
            )),

            const SizedBox(height: 40), // 리스트와 버튼 사이 간격

            // '계속하기' 버튼 (가운데 정렬)
            Center(
              child: ElevatedButton(
                onPressed: onNext, // 버튼 클릭 시 다음 화면으로 이동
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, // 버튼 배경색
                  foregroundColor: Colors.white, // 버튼 텍스트 색상
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ), // 버튼 크기
                ),
                child: const Text(
                  '계속하기',
                  style: TextStyle(fontSize: 18), // 텍스트 크기
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}