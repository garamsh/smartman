import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'account/account.dart';
import 'deck/deck.dart';
import 'shared/database.dart';
import 'shared/l10n/app_localizations.dart';
import 'study/study.dart';

/// The composition site: the one place that constructs the application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = await Scheduler.load();
  final account = await connectAccount(accountDefines());
  runApp(composeApp(driftDatabase(name: 'smartman'), scheduler, account));
}

/// Constructs the application over the database [executor] opens, scheduling
/// with the loaded [scheduler] and signing in through [account].
Widget composeApp(
  QueryExecutor executor,
  Scheduler scheduler,
  AccountService account,
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
      studyScreenProvider.overrideWithValue((deck) => StudyScreen(deck: deck)),
      accountServiceProvider.overrideWithValue(account),
      accountScreenProvider.overrideWithValue(AccountScreen.new),
    ],
    child: const SmartmanApp(),
  );
}

/// The application root, opening on the deck list.
class SmartmanApp extends StatelessWidget {
  const SmartmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DeckListScreen(),
    );
  }
}
