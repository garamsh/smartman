import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'account/account.dart';
import 'deck/deck.dart';
import 'shared/database.dart';
import 'shared/l10n/app_localizations.dart';
import 'shared/theme.dart';
import 'study/study.dart';

/// The composition site: the one place that constructs the application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = await Scheduler.load();
  final account = await connectAccount(accountDefines());
  final themeStorage = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      allowList: themeStorageKeys,
    ),
  );
  runApp(
    composeApp(
      driftDatabase(name: 'smartman'),
      scheduler,
      account,
      themeStorage,
    ),
  );
}

/// Constructs the application over the database [executor] opens, scheduling
/// with the loaded [scheduler], signing in through [account], and keeping the
/// theme choice in [themeStorage].
Widget composeApp(
  QueryExecutor executor,
  Scheduler scheduler,
  AccountService account,
  SharedPreferencesWithCache themeStorage,
) {
  final database = AppDatabase(executor);
  const uuid = Uuid();
  final deckRepository = DeckRepository(
    database,
    clock: DateTime.now,
    newId: uuid.v4,
  );
  final studyRepository = StudyRepository(database, newId: uuid.v4);
  return ProviderScope(
    overrides: [
      deckRepositoryProvider.overrideWithValue(deckRepository),
      studyRepositoryProvider.overrideWithValue(studyRepository),
      schedulerProvider.overrideWithValue(scheduler),
      studyClockProvider.overrideWithValue(DateTime.now),
      studyRandomProvider.overrideWithValue(
        (start) => Random(start.microsecondsSinceEpoch),
      ),
      studyScreenProvider.overrideWithValue(
        (decks) => StudyScreen(decks: decks),
      ),
      todayProvider.overrideWithValue(
        (decks, builder) => TodayCounter(decks: decks, builder: builder),
      ),
      accountServiceProvider.overrideWithValue(account),
      accountScreenProvider.overrideWithValue(AccountScreen.new),
      themeStorageProvider.overrideWithValue(themeStorage),
    ],
    child: const SmartmanApp(),
  );
}

/// The application root, opening on the deck list in the theme the user chose.
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
      home: const DeckListScreen(),
    );
  }
}
