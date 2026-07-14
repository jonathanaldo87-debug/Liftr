import 'package:flutter_test/flutter_test.dart';

import 'package:liftr/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LiftrApp());
    expect(find.text('Liftr'), findsWidgets);
  });
}
