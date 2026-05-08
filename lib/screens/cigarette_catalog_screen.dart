import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/remote_assets.dart';
import '../data/cigarette_collection_prefs.dart';
import '../theme/app_theme.dart';
import '../supabase/supabase_sync_service.dart';

class CigaretteCatalogScreen extends StatefulWidget {
  const CigaretteCatalogScreen({super.key});

  @override
  State<CigaretteCatalogScreen> createState() => _CigaretteCatalogScreenState();
}

class _CigaretteCatalogScreenState extends State<CigaretteCatalogScreen> {
  bool _loading = true;
  List<String> _assets = const [];
  Map<String, int> _counts = const {};

  static const int _exchangeCost = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // readCounts 내부에서 migrateLegacyListIfNeeded 가 호출된다.
    final keysFuture = RemoteAssets.fetchCigarettePackKeysCached();
    final countsFuture = CigaretteCollectionPrefs.readCounts(prefs);

    List<String> assets = const [];
    try {
      assets = await keysFuture;
    } catch (_) {
      assets = const [];
    }
    final counts = await countsFuture;

    // 수집 완료 타일이 먼저 보이므로, 프리캐시도 보유 항목을 앞에 둔다.
    final ownedKeys =
        assets.where((k) => (counts[k] ?? 0) > 0).toList(growable: false);
    final rest =
        assets.where((k) => (counts[k] ?? 0) == 0).toList(growable: false);
    final precacheOrder = <String>[...ownedKeys, ...rest];

    if (!mounted) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbDecode = (dpr * 120).round().clamp(180, 420);

    setState(() {
      _assets = assets;
      _counts = counts;
      _loading = false;
    });

    // 그리드를 먼저 열고, 그리드 타일과 동일한 디코드 폭으로 precache 해 캐시를 공유한다.
    const firstBatch = 15;
    if (precacheOrder.isNotEmpty && mounted) {
      unawaited(
        RemoteAssets.precacheFirstCigarettePackImages(
          context,
          precacheOrder,
          count: firstBatch,
          thumbnailDecodeWidth: thumbDecode,
        ),
      );
      RemoteAssets.precacheRemainingCigarettePackImagesBackground(
        context,
        precacheOrder,
        startIndex: firstBatch,
        thumbnailDecodeWidth: thumbDecode,
      );
    }
  }

  int _countFor(String asset) => _counts[asset] ?? 0;

  bool _isOwned(String asset) => _countFor(asset) > 0;

  int get _total => _assets.length;

  int get _ownedDistinct =>
      _assets.where((a) => _isOwned(a)).length;

  Future<void> _openExchangeFlow() async {
    final prefs = await SharedPreferences.getInstance();
    var counts = Map<String, int>.from(await CigaretteCollectionPrefs.readCounts(prefs));
    final assets = List<String>.from(_assets);
    if (assets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('교환할 담배갑 목록이 없습니다.')),
        );
      }
      return;
    }

    if (!mounted) return;
    final selectedGive = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        final candidates = assets
            .where((k) => (counts[k] ?? 0) >= _exchangeCost)
            .toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '교환에 사용할 담배갑',
                  style: AppTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '동일 담배갑을 $_exchangeCost개 이상 보유한 항목만 선택할 수 있어요.',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (candidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '교환 가능한 담배갑이 없습니다.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                    ),
                  )
                else
                  SizedBox(
                    height: maxH,
                    child: ListView.separated(
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final k = candidates[i];
                        final idx = assets.indexOf(k) + 1;
                        final c = counts[k] ?? 0;
                        return ListTile(
                          leading: SizedBox(
                            width: 44,
                            height: 44,
                            child: RemoteAssetImage(
                              assetKey: k,
                              fit: BoxFit.contain,
                              memCacheWidth: 120,
                            ),
                          ),
                          title: Text(
                            '#${idx.toString().padLeft(2, '0')} · $c개 보유',
                            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => Navigator.pop(ctx, k),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selectedGive == null) return;

    String? recvKey;
    if (!mounted) return;
    recvKey = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
        final candidates = assets.where((k) => (counts[k] ?? 0) == 0).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '받을 담배갑',
                  style: AppTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '아직 수집하지 않은 담배갑만 선택할 수 있어요.',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (candidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '받을 수 있는 미수집 담배갑이 없습니다.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted),
                    ),
                  )
                else
                  SizedBox(
                    height: maxH,
                    child: ListView.separated(
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final k = candidates[i];
                        final idx = assets.indexOf(k) + 1;
                        return ListTile(
                          leading: SizedBox(
                            width: 44,
                            height: 44,
                            child: Opacity(
                              opacity: 0.45,
                              child: RemoteAssetImage(
                                assetKey: k,
                                fit: BoxFit.contain,
                                memCacheWidth: 120,
                              ),
                            ),
                          ),
                          title: Text(
                            '#${idx.toString().padLeft(2, '0')} · 미수집',
                            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => Navigator.pop(ctx, k),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (recvKey == null || recvKey == selectedGive) return;

    final gk = selectedGive;
    final rk = recvKey;

    final giveCount = counts[gk] ?? 0;
    if (giveCount < _exchangeCost) return;
    if ((counts[rk] ?? 0) != 0) return;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('도감 교환'),
        content: Text(
          '선택한 담배갑 $_exchangeCost개를 사용하여\n'
          '미수집 담배갑 1개를 획득할까요?\n\n'
          '교환 후에는 사용한 담배갑이 다시 잠금 상태로 표시됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('교환')),
        ],
      ),
    );
    if (ok != true) return;

    counts[gk] = giveCount - _exchangeCost;
    if ((counts[gk] ?? 0) <= 0) {
      counts.remove(gk);
    }
    counts[rk] = 1;

    await CigaretteCollectionPrefs.writeCounts(prefs, counts);
    await SupabaseSyncService.pushLocalToRemoteIfEligible();

    if (!mounted) return;
    setState(() => _counts = counts);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('교환에 성공했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openPackPreview(String assetKey) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '담배갑 이미지',
                        style: AppTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.55,
                child: InteractiveViewer(
                  minScale: 0.6,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RemoteAssetImage(
                      assetKey: assetKey,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final owned = _ownedDistinct;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('도감'),
        actions: [
          TextButton.icon(
            onPressed: _loading ? null : _openExchangeFlow,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(
              Icons.swap_horiz_rounded,
              size: 22,
              color: Colors.white,
            ),
            label: const Text(
              '도감 교환하기',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
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
                        horizontal: 16,
                        vertical: 14,
                      ),
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
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.collections_bookmark_rounded,
                              color: AppTheme.primary,
                            ),
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
                                      ? '서버에서 담배갑 목록을 불러오지 못했습니다. API 주소와 서버 static 폴더를 확인해 주세요.'
                                      : '종류 $owned / $total · 동일 패키지는 개수로 표시됩니다.',
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
                                final count = _countFor(asset);
                                final isOwned = count > 0;
                                return _CatalogTile(
                                  index: index,
                                  asset: asset,
                                  isOwned: isOwned,
                                  count: count,
                                  onOpen: () => _openPackPreview(asset),
                                );
                              },
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
  final int count;
  final VoidCallback onOpen;

  const _CatalogTile({
    required this.index,
    required this.asset,
    required this.isOwned,
    required this.count,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbDecodeWidth = (dpr * 120).round().clamp(180, 420);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
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
                        ? RemoteAssetImage(
                            assetKey: asset,
                            fit: BoxFit.contain,
                            memCacheWidth: thumbDecodeWidth,
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: 0.42,
                                child: RemoteAssetImage(
                                  assetKey: asset,
                                  fit: BoxFit.contain,
                                  memCacheWidth: thumbDecodeWidth,
                                ),
                              ),
                              Container(
                                color: Colors.black.withValues(alpha: 0.38),
                              ),
                            ],
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
                      color: Colors.black.withValues(alpha: 0.45),
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
                if (isOwned && count > 1)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'x$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
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
        ),
      ),
    );
  }
}
