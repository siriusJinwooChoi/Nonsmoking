import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 콤마 포맷팅을 위해 추가

/// 금연 요약 정보를 보여주는 화면입니다.
/// - 1년 기준 절약 금액/안 피울 담배 개수 표시 (콤마 포맷)
/// - 현재까지 핀 담배 개수(= 하루 흡연량 × 기간) 추가 표시
class Screen9Summary extends StatelessWidget {
  final VoidCallback onNext;
  final int dailyCigarettes;     // 하루 평균 흡연량
  final int cigarettesPerPack;   // 담배 한 갑당 개비 수
  final int pricePerPack;        // 담배 한 갑 가격
  final int durationDays;        // 흡연 기간 (일 단위)

  const Screen9Summary({
    super.key,
    required this.onNext,
    required this.dailyCigarettes,
    required this.cigarettesPerPack,
    required this.pricePerPack,
    required this.durationDays,
  });

  @override
  Widget build(BuildContext context) {
    // 1년 기준 값 계산
    const int oneYearDays = 365;
    final int notSmokedInOneYear = dailyCigarettes * oneYearDays;

    // 개비당 가격(0으로 나누기 방지)
    final double costPerCigarette =
    cigarettesPerPack > 0 ? pricePerPack / cigarettesPerPack : 0;

    // 1년간 절약 금액
    final int savedMoneyYear =
    (costPerCigarette * notSmokedInOneYear).round();

    // 현재까지 핀 담배 개수 (입력된 기간 기준)
    final int smokedSoFar = dailyCigarettes * durationDays;

    // 표시용 콤마 포맷터
    final comma = NumberFormat.decimalPattern('ko_KR');
    final savedMoneyYearStr = comma.format(savedMoneyYear);
    final notSmokedInOneYearStr = comma.format(notSmokedInOneYear);
    final smokedSoFarStr = comma.format(smokedSoFar);

    // 목표 리스트 (문구만 유지)
    final List<String> goals = [
      '✔ 폐 기능 향상',
      '✔ 심혈관 건강 개선',
      '✔ 피부톤 회복',
      '✔ 체력 증가',
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              '1년간 달성할 수 있는 목표', // ✅ 문구 변경
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // 목표 리스트 출력
            ...goals.map((goal) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(goal, style: const TextStyle(fontSize: 18)),
            )),

            const SizedBox(height: 32),

            // ✅ 1년 기준 절약 금액 (₩ + 콤마)
            Text(
              '💰 1년간 절약할 수 있는 금액: ₩$savedMoneyYearStr',
              style: const TextStyle(fontSize: 20),
            ),

            const SizedBox(height: 12),

            // ✅ 1년간 안 피울 담배 수 (콤마)
            Text(
              '🚭 1년간 피우지 않을 수 있는 담배 수: $notSmokedInOneYearStr개비',
              style: const TextStyle(fontSize: 20),
            ),

            const SizedBox(height: 12),

            // ✅ 현재까지 핀 담배 개수 (기간 기반, 콤마)
            Text(
              '📦 현재까지 핀 담배 개수(추정): $smokedSoFarStr개비',
              style: const TextStyle(fontSize: 20, color: Colors.black87),
            ),

            const SizedBox(height: 40),

            // 계속하기 버튼
            Center(
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
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