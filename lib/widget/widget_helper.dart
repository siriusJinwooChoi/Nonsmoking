import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.cjw.nonsmoking/widget');

/// 홈 화면 위젯 갱신 요청 (Android 전용)
Future<void> updateHomeWidget() async {
  try {
    await _channel.invokeMethod<void>('updateWidget');
  } on MissingPluginException {
    // Android가 아니거나 위젯 미지원 시 무시
  } catch (_) {}
}

/// 앱 데이터를 위젯용 네이티브 저장소에 동기화 후 위젯 갱신.
/// Flutter SharedPreferences/DataStore와 무관하게 위젯이 동일 데이터를 표시하도록 합니다.
Future<void> syncWidgetData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getInt('startTime');
    final dailyCigarettes = prefs.getInt('dailyCigarettes') ?? 0;
    final cigarettesPerPack = prefs.getInt('cigarettesPerPack') ?? 20;
    final pricePerPack = prefs.getInt('pricePerPack') ?? 4500;
    final lungHealth = prefs.getInt('lungHealth') ?? 100;

    await _channel.invokeMethod<void>('syncWidgetData', <String, dynamic>{
      'startTime': startTime,
      'dailyCigarettes': dailyCigarettes,
      'cigarettesPerPack': cigarettesPerPack,
      'pricePerPack': pricePerPack,
      'lungHealth': lungHealth.clamp(0, 100),
    });
  } on MissingPluginException {
    // Android가 아니면 무시
  } catch (_) {}
}
