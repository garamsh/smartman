import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/media/media.dart';
import 'package:smartman/study/src/current_card.dart';

import '../media/fakes.dart';

void main() {
  final fixtures =
      (jsonDecode(
        File('../supabase/fixtures/card-frame/conversion.json')
            .readAsStringSync(),
      ) as List<Object?>).cast<Map<String, Object?>>().where(
        (fixture) => fixture['cells'] != null,
      );

  for (final fixture in fixtures) {
    testWidgets('study draws a framed card: ${fixture['name']}', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cells = decodeCells(jsonEncode(fixture['cells']));
      final sides = sidesOf(cells);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaStoreProvider.overrideWithValue(
              MediaStore(
                db,
                FakeMediaServer(),
                directory: unusedMediaDirectory,
                clock: DateTime.now,
                newId: () => 'media',
              ),
            ),
          ],
          child: MaterialApp(
            theme: lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: CurrentCard(
                  card: Card(
                    id: const CardId('card'),
                    deckId: const DeckId('deck'),
                    front: sides.front,
                    back: sides.back,
                    cardKey: frameKey(cells),
                    source: CardSource.manual,
                    createdAt: DateTime.utc(2026),
                    updatedAt: DateTime.utc(2026),
                    cells: cells,
                  ),
                  onAnswer: (_) {},
                  onGuide: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CurrentCard), findsOneWidget);
      expect(find.textContaining('cannot show'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
