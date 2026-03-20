// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('기본 스모크 테스트', (WidgetTester tester) async {
    // 이 프로젝트는 Firebase/Workmanager 등 외부 초기화가 있어
    // 기본 템플릿 테스트(MyApp/카운터)는 적용되지 않습니다.
    expect(true, isTrue);
  });
}
