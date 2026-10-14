import 'package:flutter_test/flutter_test.dart';

import 'package:smartman/main.dart';

void main() {
  testWidgets('home screen shows the app name', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartmanApp());

    expect(find.text('smartman'), findsOneWidget);
  });
}
