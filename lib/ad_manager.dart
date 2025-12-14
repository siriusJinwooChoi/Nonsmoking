import 'package:flutter/widgets.dart'; // VoidCallback
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdManager: 전면 광고(interstitial) 로드/표시 전용 싱글턴 스타일 헬퍼
class AdManager {
  AdManager._(); // 인스턴스화 방지

  // NOTE: 개발중에는 테스트 광고 ID를 사용하세요.
  // 실제 배포 시 자신의 Interstitial Ad Unit ID 로 변경하세요.
  // 앱 ID (ca-app-pub-...~...) 와는 다른 값입니다.
  // 테스트 interstitial id: Android: ca-app-pub-3940256099942544/1033173712

  static String interstitialUnitId ='ca-app-pub-2294312189421130/4538637779'; //실제 앱 광고 ID
  //static String interstitialUnitId ='ca-app-pub-3940256099942544/1033173712'; //테스트 앱 광고 ID

  static InterstitialAd? _interstitialAd;
  static bool _isLoading = false;

  /// (선택) 런타임에 광고 단위 ID 변경할 수 있게 제공
  static void setAdUnitId(String id) {
    interstitialUnitId = id;
  }

  /// 전면광고 로드
  static Future<void> loadAd() async {
    if (_isLoading || _interstitialAd != null) return;
    _isLoading = true;

    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isLoading = false;
          // 안전을 위해 광고가 로드되면 한 번만 사용되도록 콜백 비우는 등 준비.
          _interstitialAd!.setImmersiveMode(true);
        },
        onAdFailedToLoad: (LoadAdError error) {
          _interstitialAd = null;
          _isLoading = false;
          // 필요 시 디버그 로그: print('InterstitialAd failed to load: $error');
        },
      ),
    );
  }

  /// 광고 표시. 광고가 없으면 즉시 onAdClosed 호출.
  /// onAdClosed: 광고 닫힌 뒤 수행할 콜백
  static void showAd({required VoidCallback onAdClosed}) {
    final ad = _interstitialAd;
    if (ad == null) {
      // 광고가 준비되지 않으면 바로 콜백 호출하고 로드 시도
      onAdClosed();
      loadAd();
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd _) {
        // 광고가 보여지는 중
      },
      onAdDismissedFullScreenContent: (InterstitialAd displayedAd) {
        // 광고가 닫혔을 때
        try {
          displayedAd.dispose();
        } catch (_) {}
        _interstitialAd = null;
        loadAd(); // 다음 번을 위해 미리 로드
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent:
          (InterstitialAd displayedAd, AdError error) {
        try {
          displayedAd.dispose();
        } catch (_) {}
        _interstitialAd = null;
        loadAd();
        onAdClosed();
      },
    );

    // show 시도
    try {
      ad.show();
    } catch (e) {
      // 안전장치: 실패 시 콜백 호출
      _interstitialAd = null;
      loadAd();
      onAdClosed();
    }
  }

  /// (선택) 테스트/디버그용으로 현재 로드 상태 확인
  static bool get isAdLoaded => _interstitialAd != null;
}