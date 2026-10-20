import 'package:flutter_test/flutter_test.dart';

/// Waits until the open daily minutes sheet shows its picker, read by its
/// [more] step's tooltip, then lets it settle: the sheet reads the deck list
/// from a stream, which delivers on real time.
Future<void> waitForPicker(
  WidgetTester tester, {
  String more = '5 minutes more',
}) async {
  for (var tries = 0; find.byTooltip(more).evaluate().isEmpty; tries++) {
    if (tries == 100) fail('the sheet never showed its picker');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
