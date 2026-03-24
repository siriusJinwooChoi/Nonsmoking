import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 메인 화면과 동일한 배너 단위 ID (하단 고정 배너용).
class BannerAdBar extends StatefulWidget {
  const BannerAdBar({super.key});

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> {
  BannerAd? _banner;
  bool _ready = false;

  static const String _adUnitId = 'ca-app-pub-2294312189421130/2526201037';

  @override
  void initState() {
    super.initState();
    final banner = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _banner = ad as BannerAd;
            _ready = true;
          });
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _banner = null;
            _ready = false;
          });
        },
      ),
    );
    banner.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _banner == null) {
      return const SizedBox(height: 0);
    }
    return SizedBox(
      width: double.infinity,
      height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }
}
