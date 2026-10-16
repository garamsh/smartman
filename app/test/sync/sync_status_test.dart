import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/design/theme_choice.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';

import '../account/fake_account_service.dart';
import 'device.dart';
import 'fake_sync_server.dart';

const _ada = UserId('00000000-0000-4000-8000-00000000000a');

void main() {
  late Scheduler scheduler;
  setUpAll(() async => scheduler = await Scheduler.load());

  /// The account screen, signed in, over a sync controller that runs only
  /// when the test asks it to.
  Future<(SyncController, FakeSyncServer)> pumpScreen(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final storage = (await tester.runAsync(
      () => SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: themeStorageKeys,
        ),
      ),
    ))!;
    final server = FakeSyncServer(_ada);
    final device = Device('device', server, scheduler);
    final account = FakeAccountService(
      const SignedIn(userId: _ada, email: 'ada@example.com'),
    );
    final controller = SyncController(
      account: account,
      synchronizer: device.synchronizer,
      store: device.store,
      edits: const Stream.empty(),
      firstRetry: const Duration(hours: 1),
    );
    addTearDown(() async {
      controller.dispose();
      await tester.runAsync(device.close);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountServiceProvider.overrideWithValue(account),
          appVersionProvider.overrideWithValue('1.0.0'),
          accountDataProvider.overrideWithValue(controller),
          syncControllerProvider.overrideWithValue(controller),
          themeStorageProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AccountScreen(syncStatus: SyncStatusView()),
        ),
      ),
    );
    return (controller, server);
  }

  Future<void> runSync(WidgetTester tester, SyncController controller) async {
    await tester.runAsync(controller.sync);
    await tester.pump();
  }

  testWidgets('a run under way shows syncing', (tester) async {
    final (controller, server) = await pumpScreen(tester);
    server.stall = true;

    unawaited(controller.sync());
    await tester.pump();

    expect(find.text('Syncing'), findsOneWidget);
  });

  testWidgets('a finished run shows synced, in Korean', (tester) async {
    final (controller, _) = await pumpScreen(
      tester,
      locale: const Locale('ko'),
    );
    expect(find.text('동기화됨'), findsNothing);

    await runSync(tester, controller);

    expect(find.text('동기화됨'), findsOneWidget);
  });

  testWidgets('an offline run shows offline, with no retry button', (
    tester,
  ) async {
    final (controller, server) = await pumpScreen(tester);
    server.failure = const SyncOffline('no route to host');

    await runSync(tester, controller);

    expect(find.text('Offline · syncs when connected'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  for (final failure in [
    const SyncRejected(FormatException('expired')),
    const SyncFailed(FormatException('bad row')),
  ]) {
    testWidgets('${failure.runtimeType} shows a failure whose retry syncs', (
      tester,
    ) async {
      final (controller, server) = await pumpScreen(tester);
      server.failure = failure;
      await runSync(tester, controller);
      expect(find.text("Couldn't sync"), findsOneWidget);

      server.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.runAsync(controller.sync);
      await tester.pump();

      expect(find.text('Synced'), findsOneWidget);
      expect(find.text("Couldn't sync"), findsNothing);
    });
  }

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the failure line meets the tap target and contrast guidelines '
        'in the ${themeMode.name} theme', (tester) async {
      final (controller, server) = await pumpScreen(
        tester,
        themeMode: themeMode,
      );
      server.failure = const SyncFailed(FormatException('bad row'));
      await runSync(tester, controller);
      expect(find.text('Try again'), findsOneWidget);

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  }
}
