import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Lets file and database writes outside the test's fake time run, a slice
/// of real time and then a frame as long at a time, until [done] holds; fails
/// naming [what] after 10 s. Such writes take real time, so a fixed count of
/// slices runs out first on a slow machine.
Future<void> settleUntil(
  WidgetTester tester,
  String what,
  FutureOr<bool> Function() done,
) async {
  const slice = Duration(milliseconds: 10);
  final waited = Stopwatch()..start();
  while (!await done()) {
    if (waited.elapsed > const Duration(seconds: 10)) {
      fail('waited 10 s for $what');
    }
    await tester.runAsync(() => Future<void>.delayed(slice));
    await tester.pump(slice);
  }
  await tester.pumpAndSettle();
}
