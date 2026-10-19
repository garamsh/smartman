import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/study.dart';

/// Opens the device storage of the study screen and the card editor in memory, holding its coach as
/// shown unless [coachShown] is false, so a test that opens a session meets
/// the coach only where it asks for a device's first session.
Future<SharedPreferencesWithCache> openStudyStorage(
  WidgetTester tester, {
  bool coachShown = true,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        if (coachShown) studyCoachShownKey: true,
      });
  return (await tester.runAsync(
    () => SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {...studyStorageKeys, ...deckStorageKeys},
      ),
    ),
  ))!;
}
