import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:knowno/deck/deck.dart';
import 'package:knowno/study/study.dart';

/// Opens the device storage of the study screen and the card editor in memory, holding its coach as
/// shown unless [coachShown] is false, and the first-run daily minutes step
/// as shown unless [minutesAsked] is false, so a test meets either only where
/// it asks for a device's first time; [autoplay], when given, is stored as
/// the autoplay setting.
Future<SharedPreferencesWithCache> openStudyStorage(
  WidgetTester tester, {
  bool coachShown = true,
  bool minutesAsked = true,
  bool? autoplay,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        if (coachShown) studyCoachShownKey: true,
        if (minutesAsked) dailyMinutesAskedKey: true,
        autoplayAudioKey: ?autoplay,
      });
  return (await tester.runAsync(
    () => SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {...studyStorageKeys, ...deckStorageKeys},
      ),
    ),
  ))!;
}
