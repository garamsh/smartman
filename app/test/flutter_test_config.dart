import 'dart:async';

import 'package:smartman/study/src/rust/frb_generated.dart';

/// Loads the engine library once before every test file, as the composition
/// site does before `runApp`: a study session places its cards through the
/// engine's today's list, a synchronous call.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await RustLib.init();
  await testMain();
}
