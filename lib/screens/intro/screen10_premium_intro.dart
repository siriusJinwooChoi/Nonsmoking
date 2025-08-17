import 'package:flutter/material.dart';

class Screen10PremiumIntro extends StatelessWidget {
  final VoidCallback onNext;
  const Screen10PremiumIntro({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final List<String> features = [
      '✔ 광고 제거',
      '✔ 1년까지 금연 목표 지원',
      '✔ 나무를 성장시킴으로써 금연 목표 확실히!',
    ];

    return Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text(
            '프리미엄 기능을 통해 금연 성공률을 높이세요!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          const Text(
              '담배 한 갑의 가격으로 당신의 건강을 바꾸세요.'
              '프리미엄은 다음 기능을 포함합니다:',
              style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 20),
        ...features.map((f) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(f, style: const TextStyle(fontSize: 18)),
    )),
    const SizedBox(height: 40),
    Center(
    child: ElevatedButton(
    onPressed: onNext,
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
    ),
    child: const Text('프리미엄 없이 계속하기', style: TextStyle(fontSize: 18)),
    ),
    ),
    ],
    ),
    ),
    );
  }
}