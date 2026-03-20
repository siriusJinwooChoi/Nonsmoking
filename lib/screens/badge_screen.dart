import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// 금연 뱃지 화면: 피우지 않은 담배 개수·금연 일수 기준 뱃지
class BadgeScreen extends StatefulWidget {
  const BadgeScreen({super.key});

  @override
  State<BadgeScreen> createState() => _BadgeScreenState();
}

class _BadgeScreenState extends State<BadgeScreen> {
  int _quitDays = 0;
  int _skippedCigarettes = 0;
  int _dailyCigarettes = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt('startTime');
    _dailyCigarettes = prefs.getInt('dailyCigarettes') ?? 0;

    if (millis != null) {
      final start = DateTime.fromMillisecondsSinceEpoch(millis);
      final now = DateTime.now();
      _quitDays = now.difference(start).inDays;
      final seconds = now.difference(start).inSeconds;
      if (_dailyCigarettes > 0) {
        final totalCigs = (_dailyCigarettes / (24 * 60 * 60)) * seconds;
        _skippedCigarettes = totalCigs.floor();
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('금연 뱃지'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          _sectionTitle('피우지 않은 담배 개수'),
          _badgeGrid(
            values: const [20, 50, 100, 200, 500, 1000, 10000],
            achieved: _skippedCigarettes,
            labelBuilder: (v) => '$v개비',
          ),
          const SizedBox(height: 24),
          _sectionTitle('금연 일수'),
          _badgeGrid(
            values: const [1, 3, 7, 10, 14, 30, 90, 180, 365, 730],
            achieved: _quitDays,
            labelBuilder: (v) => '${v}일',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text,
        style: AppTheme.titleMedium.copyWith(
          color: AppTheme.primary,
        ),
      ),
    );
  }

  Widget _badgeGrid({
    required List<int> values,
    required int achieved,
    required String Function(int) labelBuilder,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final v = values[index];
        final unlocked = achieved >= v;
        return _BadgeChip(
          value: labelBuilder(v),
          unlocked: unlocked,
          tier: index,
        );
      },
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String value;
  final bool unlocked;
  final int tier;

  const _BadgeChip({required this.value, required this.unlocked, this.tier = 0});

  static IconData _iconForTier(int tier, bool unlocked) {
    if (!unlocked) return Icons.emoji_events_outlined;
    switch (tier % 4) {
      case 0: return Icons.star_rounded;
      case 1: return Icons.military_tech_rounded;
      case 2: return Icons.emoji_events_rounded;
      default: return Icons.diamond_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadowSubtle,
        border: Border.all(
          color: unlocked ? AppTheme.primary.withOpacity(0.4) : AppTheme.textMuted.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForTier(tier, unlocked),
            size: 28,
            color: unlocked ? AppTheme.warning : AppTheme.textMuted,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.titleMedium.copyWith(
              fontSize: 11,
              color: unlocked ? AppTheme.textPrimary : AppTheme.textMuted,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
