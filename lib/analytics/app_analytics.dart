import 'package:firebase_analytics/firebase_analytics.dart';

class AppAnalytics {
  AppAnalytics._();

  static final FirebaseAnalytics instance = FirebaseAnalytics.instance;

  static Future<void> log(
      String name, {
        Map<String, Object?>? params,
      }) {
    // ✅ null 값 제거 + Map<String, Object>로 변환
    final Map<String, Object>? cleaned = params
        ?.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, e.value as Object))
        .fold<Map<String, Object>>({}, (map, e) {
      map[e.key] = e.value;
      return map;
    });

    return instance.logEvent(
      name: name,
      parameters: cleaned,
    );
  }

  static Future<void> screen(String screenName) {
    return instance.logScreenView(screenName: screenName);
  }
}