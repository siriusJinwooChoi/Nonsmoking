import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NonsmokeHelperScreen extends StatelessWidget {
  const NonsmokeHelperScreen({super.key});

  final List<Map<String, String>> tips = const [
    {
      'title': '자신의 사진을 찍으세요',
      'description': '비흡연자로서 자신의 모습을 기록하세요.',
      'icon': '🧠'
    },
    {
      'title': '금연 방법을 공유받기',
      'description': '비흡연자에게 금연 방법을 들어보세요.',
      'icon': '💬'
    },
    {
      'title': '정보 읽기',
      'description': '금연에 대한 모든 정보를 읽어보세요.',
      'icon': '🔍'
    },
    {
      'title': '금연 이유 점검',
      'description': '흡연하고 싶을 때 이 이유를 확인하세요.',
      'icon': '📝'
    },
    {
      'title': '기분 일기 쓰기',
      'description': '기분이 좋아질 때까지의 과정을 기록하세요.',
      'icon': '📓'
    },
    {
      'title': '담배 대신 저축',
      'description': '담배값을 모아 특별한 계획에 써보세요.',
      'icon': '🎁'
    },
    {
      'title': '친구와 함께 금연',
      'description': '서로 격려하며 함께 실천해보세요.',
      'icon': '🤝'
    },
    {
      'title': '피해주지 않기',
      'description': '비흡연자 앞에서 흡연을 삼가세요.',
      'icon': '🚫'
    },
    {
      'title': '간식 활용',
      'description': '과일이나 견과류를 손에 자주 쥐세요.',
      'icon': '🍎'
    },
    {
      'title': '카페인/술 줄이기',
      'description': '흡연 욕구를 자극하는 요소를 피하세요.',
      'icon': '☕'
    },
    {
      'title': '흡연 유도 환경 피하기',
      'description': '초반에는 흡연 상황을 피하세요.',
      'icon': '🚷'
    },
    {
      'title': '담배/라이터 버리기',
      'description': '금연 결심을 강화하는 행동입니다.',
      'icon': '🗑️'
    },
    {
      'title': '자동차 청소하기',
      'description': '담배 냄새 제거로 새로운 시작을 하세요.',
      'icon': '🚗'
    },
    {
      'title': '집 청소하기',
      'description': '흡연 흔적을 없애보세요.',
      'icon': '🧹'
    },
    {
      'title': '옷 세탁하기',
      'description': '흡연 냄새 제거로 상쾌함을 느끼세요.',
      'icon': '👕'
    },
    {
      'title': '목욕과 샤워',
      'description': '긴장을 풀고 욕구를 덜어냅니다.',
      'icon': '🛁'
    },
    {
      'title': '산책하기',
      'description': '몸과 마음을 가볍게 하세요.',
      'icon': '🚶‍♂️'
    },
    {
      'title': '음악 듣기',
      'description': '기분 전환과 스트레스 해소에 좋아요.',
      'icon': '🎧'
    },
    {
      'title': '실패해도 괜찮아요',
      'description': '실패는 과정의 일부일 뿐입니다.',
      'icon': '💪'
    },
    {
      'title': '자유를 즐기세요',
      'description': '시간은 당신의 편입니다.',
      'icon': '🍸'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('금연 도우미'),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: tips.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final tip = tips[index];
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadowSubtle,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(tip['icon']!, style: const TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tip['title']!,
                          style: AppTheme.titleMedium.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tip['description']!,
                          style: AppTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}