// Flutter UI 구성에 필요한 기본 패키지
import 'package:flutter/material.dart';

/// 금연을 시작한 사용자를 응원하는 첫 번째 온보딩 화면
/// [onNext] 콜백을 통해 다음 화면으로 이동 가능
class Screen1Encourage extends StatelessWidget {
  final VoidCallback onNext; // '계속하기' 버튼 클릭 시 실행할 콜백 함수

  // 생성자에서 onNext를 필수 파라미터로 받음
  const Screen1Encourage({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 전체 화면 배경색 흰색

      // 내용에 여백 추가
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // 세로 방향 중앙 정렬
          crossAxisAlignment: CrossAxisAlignment.center, // 가로 방향 중앙 정렬

          children: [
            // 금연 응원 메시지
            const Text(
              '오늘 당신은 금연을 선택했어요.\n삶을 바꾸게 해드릴게요.\n당신을 응원합니다! :)',
              style: TextStyle(
                fontSize: 24, // 글자 크기
                fontWeight: FontWeight.bold, // 굵은 글씨
              ),
              textAlign: TextAlign.center, // 텍스트 중앙 정렬
            ),

            const SizedBox(height: 40), // 메시지와 버튼 사이 간격

            // '계속하기' 버튼
            ElevatedButton(
              onPressed: onNext, // 클릭 시 다음 화면으로 이동
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // 버튼 배경색
                foregroundColor: Colors.white, // 텍스트 색상
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ), // 버튼 패딩
              ),
              child: const Text(
                '계속하기',
                style: TextStyle(fontSize: 18), // 버튼 글자 크기
              ),
            ),
          ],
        ),
      ),
    );
  }
}