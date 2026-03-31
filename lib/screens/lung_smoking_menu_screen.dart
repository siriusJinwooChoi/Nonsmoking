import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad_bar.dart';
import 'lung_screen.dart';
import 'smoking_screen.dart';

/// 폐·건강 메뉴 선택 화면
class LungSmokingMenuScreen extends StatelessWidget {
  const LungSmokingMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('폐 · 건강'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      '확인할 화면을 선택하세요',
                      style: AppTheme.titleMedium.copyWith(color: AppTheme.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _MenuCard(
                      icon: Icons.favorite_rounded,
                      title: '나의 폐 건강',
                      subtitle: '폐 회복 상태와 회복 속도를 확인합니다.',
                      color: AppTheme.success,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LungScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _MenuCard(
                      icon: Icons.movie_filter_rounded,
                      title: '담타시간(실시간 커뮤니티)',
                      subtitle: '담타 루틴을 체험하며 다시 복귀를 준비해요.',
                      color: AppTheme.error,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SmokingScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const BannerAdBar(),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.cardShadowSubtle,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 30, color: color),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.titleMedium.copyWith(fontSize: 16),
                    ),
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

