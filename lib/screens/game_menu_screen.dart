import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';
import 'word_game_screen.dart';
import 'cigarette_catch_game_screen.dart';
import 'timing_tap_game_screen.dart';
import 'game_ranking_screen.dart';

/// 게임 선택: 1-30 숫자 게임 / 단어맞추기 / 담배맞추기 / 완벽 타이밍
class GameMenuScreen extends StatelessWidget {
  const GameMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('게임'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GameRankingScreen()),
              );
            },
            icon: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 22),
            label: const Text('랭킹', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                '플레이할 게임을 선택하세요',
                style: AppTheme.titleMedium.copyWith(color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _GameCard(
                icon: Icons.numbers_rounded,
                title: '1부터 30까지 빠르게!',
                subtitle: '숫자를 순서대로 탭해서 완료하세요',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GameScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _GameCard(
                icon: Icons.text_fields_rounded,
                title: '단어맞추기',
                subtitle: '섞인 글자를 순서대로 맞춰 보세요',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WordGameScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _GameCard(
                icon: Icons.smoking_rooms_rounded,
                title: '담배맞추기',
                subtitle: '떨어지는 담배를 맞춰 보세요 (1~100단계)',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CigaretteCatchGameScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              _GameCard(
                icon: Icons.speed_rounded,
                title: '완벽 타이밍',
                subtitle: '움직이는 표시가 중앙에 올 때 탭해 보세요',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimingTapGameScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.cardShadowSubtle,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 36, color: AppTheme.primary),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
