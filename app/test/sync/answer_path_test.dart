import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/main.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';
import 'package:smartman/shared/ui/app_text_field.dart';

import '../account/fake_account_service.dart';
import '../sharing/fakes.dart';
import 'fake_sync_server.dart';

const _ada = UserId('00000000-0000-4000-8000-00000000000a');

void main() {
  late Scheduler scheduler;
  setUpAll(() async => scheduler = await Scheduler.load());

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('answering advances while a sync run never finishes', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final themeStorage = (await tester.runAsync(
      () => SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: themeStorageKeys,
        ),
      ),
    ))!;
    final server = FakeSyncServer(_ada)..stall = true;
    await tester.pumpWidget(
      composeApp(
        NativeDatabase.memory(),
        scheduler,
        FakeAccountService(const SignedIn(userId: _ada, email: null)),
        server,
        themeStorage,
        null,
        null,
        FakeReachability(),
      ),
    );
    await tester.pumpAndSettle();
    final sync = ProviderScope.containerOf(tester.element(find.text('Decks')))
        .read(syncControllerProvider);

    await tapAndSettle(tester, 'New deck');
    await tester.enterText(find.widgetWithText(AppTextField, 'Name'), 'French');
    await tapAndSettle(tester, 'Create');
    await tapAndSettle(tester, 'French');
    for (final (front, back) in [('Chat', 'cat'), ('Chien', 'dog')]) {
      await tapAndSettle(tester, 'Add card');
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Question'),
        front,
      );
      await tester.enterText(find.widgetWithText(AppTextField, 'Answer'), back);
      await tapAndSettle(tester, 'Save');
    }
    await tapAndSettle(tester, 'Study · 2');
    // The run that started with the app is still waiting on the server.
    expect(sync.status.value, isA<Syncing>());
    expect(server.requests, isEmpty);
    expect(find.text('0 / 2'), findsOneWidget);
    final first = find.text('Chat').evaluate().isEmpty ? 'Chien' : 'Chat';

    await tester.timedDrag(
      find.text(first),
      const Offset(200, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(sync.status.value, isA<Syncing>());

    sync.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
