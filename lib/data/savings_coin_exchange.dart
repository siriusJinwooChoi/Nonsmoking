import 'package:shared_preferences/shared_preferences.dart';

/// 절약 금액(원) 중 이미 금연코인으로 바꾼 누적액. [computeTheoreticalSavedWon] − 이 값 = 환전 가능 금액.
const String kSavingsExchangedToCoinsWonKey = 'savings_exchanged_to_coins_won';

/// 1코인 = 100원
const int kWonPerSavingsCoin = 100;

/// 메인 화면과 동일한 공식으로 이론적 누적 절약액(원, 내림).
int computeTheoreticalSavedWon({
  required DateTime startTime,
  required int dailyCigarettes,
  required int cigarettesPerPack,
  required int pricePerPack,
}) {
  final now = DateTime.now();
  var diff = now.difference(startTime);
  if (diff.isNegative) diff = Duration.zero;
  final seconds = diff.inSeconds;
  final totalCigs = (dailyCigarettes / (24 * 60 * 60)) * seconds;
  final costPerCig =
      cigarettesPerPack > 0 ? pricePerPack / cigarettesPerPack : 0.0;
  final money = totalCigs * costPerCig;
  return money.floor().clamp(0, 0x7fffffff);
}

Future<int> readSavingsExchangedToCoinsWon() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(kSavingsExchangedToCoinsWonKey) ?? 0;
}

Future<void> writeSavingsExchangedToCoinsWon(int value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kSavingsExchangedToCoinsWonKey, value.clamp(0, 0x7fffffff));
}
