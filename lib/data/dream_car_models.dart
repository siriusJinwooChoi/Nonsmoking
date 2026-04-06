import 'dart:math' as math;

/// 나의 드림카 — 브랜드별 단계 이름·원격 이미지 키.
///
/// 서버 `public/app-assets` 가 `/static/` 으로 노출될 때 아래 경로에 파일을 올려주세요.
/// 예: `dreamcar/hcompany/stage_1.png` … `dreamcar/hcompany/stage_10.png`
///     `dreamcar/kcompany/stage_1.png` … `dreamcar/kcompany/stage_10.png`
/// (로컬 `D:\...\2. 현대`, `1. 기아` 폴더의 1~10단계 이미지를 위 이름으로 업로드)
abstract final class DreamCarCatalog {
  static const int maxStage = 10;
  static const int tierDays = 30;

  /// 하루 적립되는 금연 머니(원). 30일이면 [wonPerTier].
  static const int wonPerDay = 250000;

  /// 한 단계 업그레이드에 필요한 누적 금액(원) = 30일 분.
  static const int wonPerTier = wonPerDay * tierDays; // 7,500,000

  /// 누적 상한(원). 10단계 분 = 75,000,000.
  static const int maxTotalWon = wonPerTier * maxStage;

  /// **테스트 전용:** `true`이면 1초당 [rapidTestWonPerSecond]원 적립.
  /// **스토어/실서비스 배포 전에는 반드시 `false`로 바꾸세요.** (원래: 하루 [wonPerDay]원)
  static const bool kDreamCarRapidMoneyTestEnabled = false;

  /// [kDreamCarRapidMoneyTestEnabled] 가 true일 때만 사용.
  static const int rapidTestWonPerSecond = 500000;

  static int get _dayMs => const Duration(days: 1).inMilliseconds;

  /// 금연 시작 시각부터의 경과(ms)로 산출한 누적 금연 머니(원). 업그레이드해도 0으로 리셋되지 않음.
  static int quitMoneyFromElapsedMs(int elapsedMs) {
    if (elapsedMs <= 0) return 0;
    final int raw;
    if (kDreamCarRapidMoneyTestEnabled) {
      raw = (elapsedMs ~/ Duration.millisecondsPerSecond) * rapidTestWonPerSecond;
    } else {
      raw = (elapsedMs / _dayMs * wonPerDay).floor();
    }
    return raw.clamp(0, maxTotalWon);
  }

  /// 현재 [stage]에서 다음 단계로 가기 위해 필요한 누적 금액(원).
  static int thresholdWonForUpgradeFromStage(int stage) {
    if (stage < 1 || stage >= maxStage) return 0;
    return stage * wonPerTier;
  }

  static bool canUpgradeWithMoney(int stage, int totalQuitMoney) {
    if (stage < 1 || stage >= maxStage) return false;
    return totalQuitMoney >= thresholdWonForUpgradeFromStage(stage);
  }

  static int wonRemainingUntilNextUpgrade(int stage, int totalQuitMoney) {
    if (stage >= maxStage) return 0;
    final need = thresholdWonForUpgradeFromStage(stage);
    return math.max(0, need - totalQuitMoney);
  }

  /// 현재 단계 구간(이전 임계 ~ 다음 임계)에서의 게이지 0~1.
  static double moneyGaugeProgress(int stage, int totalQuitMoney) {
    if (stage >= maxStage) return 1.0;
    final lower = (stage - 1) * wonPerTier;
    final upper = stage * wonPerTier;
    final span = upper - lower;
    if (span <= 0) return 1.0;
    return ((totalQuitMoney - lower) / span).clamp(0.0, 1.0);
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
