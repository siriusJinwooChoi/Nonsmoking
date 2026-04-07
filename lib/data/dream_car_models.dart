import 'dart:math' as math;

/// 나의 드림카 — 브랜드별 단계 이름·원격 이미지 키.
///
/// 서버 `public/app-assets` 가 `/static/` 으로 노출될 때 아래 경로에 파일을 올려주세요.
/// 예: `dreamcar/hcompany/stage_1.png` … `dreamcar/hcompany/stage_10.png`
///     `dreamcar/kcompany/stage_1.png` … `dreamcar/kcompany/stage_10.png`
abstract final class DreamCarCatalog {
  static const int maxStage = 10;

  /// 단계당 필요 금연코인(출석·게임·절약 환전 등으로 모은 코인).
  static const int coinsPerUpgrade = 1500;

  static bool canUpgradeWithCoins(int stage, int coinBalance) {
    if (stage < 1 || stage >= maxStage) return false;
    return coinBalance >= coinsPerUpgrade;
  }

  static int coinsRemainingForNextUpgrade(int stage, int coinBalance) {
    if (stage >= maxStage) return 0;
    return math.max(0, coinsPerUpgrade - coinBalance);
  }

  /// 현재 단계에서 다음 업그레이드까지 코인 진행률 0~1.
  static double coinGaugeProgressForNextUpgrade(int stage, int coinBalance) {
    if (stage >= maxStage) return 1.0;
    return (coinBalance / coinsPerUpgrade).clamp(0.0, 1.0);
  }

  static String assetKey(String brand, int stage) {
    final s = stage.clamp(1, maxStage);
    return 'dreamcar/$brand/stage_$s.png';
  }

  static const List<String> hcompanyModelNames = [
    '캐스퍼',
    'i20',
    '코나',
    '투싼',
    '싼타페',
    '팰리세이드',
    '아이오닉 5',
    '아이오닉 6',
    '그랜저',
    '제네시스',
  ];

  static const List<String> kcompanyModelNames = [
    '모닝',
    '레이',
    '셀토스',
    '스포티지',
    '쏘렌토',
    '카니발',
    'EV3',
    'EV6',
    'K8',
    'EV9',
  ];

  static String modelName(String brand, int stage) {
    final idx = (stage - 1).clamp(0, maxStage - 1);
    if (brand == 'hcompany' || brand == 'hyundai') return hcompanyModelNames[idx];
    return kcompanyModelNames[idx];
  }
}
