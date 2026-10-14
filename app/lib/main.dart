import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'deck/deck.dart';
import 'shared/database.dart';
import 'shared/l10n/app_localizations.dart';

/// The composition site: the one place that constructs the application.
void main() {
  runApp(composeApp(driftDatabase(name: 'smartman')));
}

/// Constructs the application over the database [executor] opens.
Widget composeApp(QueryExecutor executor) {
  final database = AppDatabase(executor);
  final deckRepository = DeckRepository(
    database,
    clock: DateTime.now,
    newId: const Uuid().v4,
  );
  return ProviderScope(
    overrides: [deckRepositoryProvider.overrideWithValue(deckRepository)],
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
