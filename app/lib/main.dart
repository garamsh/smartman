import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'account/account.dart';
import 'database/database.dart';
import 'deck/deck.dart';
import 'design/theme.dart';
import 'design/theme_choice.dart';
import 'home/home.dart';
import 'l10n/app_localizations.dart';
import 'photo_import/photo_import.dart';
import 'sharing/sharing.dart';
import 'study/study.dart';
import 'sync/sync.dart';

/// The composition site: the one place that constructs the application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = await Scheduler.load();
  final account = await connectAccount(accountDefines());
  final package = await PackageInfo.fromPlatform();
  final preferences = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      allowList: {
        ...themeStorageKeys,
        ...photoImportStorageKeys,
        ...studyStorageKeys,
        ...deckStorageKeys,
      },
    ),
  );
  runApp(
    composeApp(
      driftDatabase(name: 'smartman'),
      scheduler,
      account.service,
      connectSyncServer(account),
      preferences,
      switch (account.client) {
        final client? => HttpExtractionClient(
          http.Client(),
          functionUrl: extractCardsUrl(client.rest.url),
          accessToken: () async => client.auth.currentSession?.accessToken,
        ),
        null => null,
      },
      switch (account.client) {
        final client? => SupabaseSharingServer(client),
        null => null,
      },
      DeviceReachability(),
      package.version,
    ),
  );
}

/// Constructs the application over the database [executor] opens, scheduling
/// with the loaded [scheduler], signing in through [account], syncing with
/// [server], keeping the theme choice and whether photo import's and the
/// study screen's coaches have shown in [preferences], extracting cards from
/// photos through [extraction], whose absence hides photo import, and sharing
/// decks through [sharing] while [reachability] says the device is online;
/// without [sharing] the app offers no sharing. The account screen names the
/// app's [version]. Sync starts at once.
Widget composeApp(
  QueryExecutor executor,
  Scheduler scheduler,
  AccountService account,
  SyncServer server,
  SharedPreferencesWithCache preferences,
  ExtractionClient? extraction,
  SharingServer? sharing,
  Reachability reachability,
  String version,
) {
  final database = AppDatabase(executor);
  const uuid = Uuid();
  final deckRepository = DeckRepository(
    database,
    clock: DateTime.now,
    newId: uuid.v7,
  );
  final studyRepository = StudyRepository(database, newId: uuid.v7);
  final syncStore = SyncStore(database, scheduler, clock: DateTime.now);
  final sync = SyncController(
    account: account,
    synchronizer: Synchronizer(syncStore, server),
    store: syncStore,
    edits: database.tableUpdates(
      TableUpdateQuery.onAllTables([
        database.decks,
        database.cards,
        database.reviews,
        database.cardStates,
        database.studySettings,
      ]),
    ),
  )..start();
  return ProviderScope(
    overrides: [
      deckRepositoryProvider.overrideWithValue(deckRepository),
      sharingServiceProvider.overrideWithValue(
        sharing == null
            ? null
            : SharingService(
                server: sharing,
                decks: deckRepository,
                reachability: reachability,
                clock: DateTime.now,
              ),
      ),
      photoImportProvider.overrideWithValue(
        extraction == null
            ? null
            : (context, deck, origin) => importFromPhoto(
                context,
                deck: deck,
                origin: origin,
                client: extraction,
                photos: const DevicePhotoSource(),
                preferences: preferences,
              ),
      ),
      studyRepositoryProvider.overrideWithValue(studyRepository),
      schedulerProvider.overrideWithValue(scheduler),
      studyClockProvider.overrideWithValue(DateTime.now),
      studyZoneProvider.overrideWithValue(localOffsetAt),
      studyStorageProvider.overrideWithValue(preferences),
      studyRandomProvider.overrideWithValue(
        (start) => Random(start.microsecondsSinceEpoch),
      ),
      accountServiceProvider.overrideWithValue(account),
      appVersionProvider.overrideWithValue(version),
      accountDataProvider.overrideWithValue(sync),
      syncControllerProvider.overrideWithValue(sync),
      themeStorageProvider.overrideWithValue(preferences),
      deckStorageProvider.overrideWithValue(preferences),
    ],
    child: const SmartmanApp(),
  );
}

/// The application root, opening on the account gate in the theme the user
/// chose.
class SmartmanApp extends ConsumerWidget {
  const SmartmanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AccountGate(signedIn: HomeScreen()),
    );
  }
}
