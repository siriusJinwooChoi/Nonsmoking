import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class CigaretteCatalogScreen extends StatefulWidget {
  const CigaretteCatalogScreen({super.key});

  @override
  State<CigaretteCatalogScreen> createState() => _CigaretteCatalogScreenState();
}

class _CigaretteCatalogScreenState extends State<CigaretteCatalogScreen> {
  static const String _collectedKey = 'collected_cigarette_assets';

  bool _loading = true;
  List<String> _assets = const [];
  Set<String> _collected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final collectedList = prefs.getStringList(_collectedKey) ?? <String>[];
    final collectedSet = collectedList.toSet();

    List<String> assets = const [];
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest =
          json.decode(manifestJson) as Map<String, dynamic>;
      assets = manifest.keys
          .where((k) {
            if (!k.startsWith('assets/cigarettes/')) return false;
            final lower = k.toLowerCase();
            return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg');
          })
          .toList()
        ..sort();
    } catch (_) {
      assets = const [];
    }

    if (!mounted) return;
    setState(() {
      _assets = assets;
      _collected = collectedSet;
      _loading = false;
    });
  }

  Future<void> _resetCollected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('수집 초기화'),
        content: const Text('수집한 담배갑 기록을 모두 초기화할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_collectedKey);
    if (!mounted) return;
    setState(() {
      _collected = {};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('수집 기록을 초기화했습니다.'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _assets.length;
    final owned = _assets.where(_collected.contains).length;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('도감'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.cardShadowSubtle,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.collections_bookmark_rounded,
                                color: AppTheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('수집 현황', style: AppTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  total == 0
                                      ? '이미지를 불러올 수 없습니다. assets/cigarettes 및 pubspec.yaml 설정을 확인해 주세요.'
                                      : '$owned / $total 수집',
                                  style: AppTheme.bodyMedium
                                      .copyWith(color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: total == 0
                          ? Center(
                              child: Text(
                                '담배갑 이미지가 없습니다.',
                                style: AppTheme.bodyMedium
                                    .copyWith(color: AppTheme.textMuted),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: total,
                              itemBuilder: (context, index) {
                                final asset = _assets[index];
                                final isOwned = _collected.contains(asset);
                                return _CatalogTile(
                                  index: index,
                                  asset: asset,
                                  isOwned: isOwned,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _resetCollected,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('담배갑 수집 초기화'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: BorderSide(color: AppTheme.error.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final int index;
  final String asset;
  final bool isOwned;

  const _CatalogTile({
    required this.index,
    required this.asset,
    required this.isOwned,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadowSubtle,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: isOwned
                    ? Image.asset(
                        asset,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.image_not_supported_rounded,
                              color: AppTheme.textMuted),
                        ),
                      )
                    : Container(
                        color: Colors.black,
                      ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (!isOwned)
              const Positioned.fill(
                child: Center(
                  child: Icon(
                    Icons.lock_rounded,
                    color: Colors.white70,
                    size: 26,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

