import 'package:flutter_test/flutter_test.dart';

/// Waits until the open daily minutes sheet shows its choices, among them
/// [choice], then lets it settle: the sheet reads the deck list from a
/// stream, which delivers on real time.
Future<void> waitForChoices(
  WidgetTester tester, {
  String choice = '10 min',
}) async {
  for (var tries = 0; find.text(choice).evaluate().isEmpty; tries++) {
    if (tries == 100) fail('the sheet never showed its choices');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
