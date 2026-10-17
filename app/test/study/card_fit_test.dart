import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/card_text.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';
import 'package:smartman/study/src/current_card.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/previous_card.dart';
import 'package:smartman/study/src/providers.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/study_repository.dart';
import 'package:smartman/study/src/study_screen.dart';
import 'package:smartman/study/src/study_style.dart';

import 'fixtures.dart';

// Pretendard is loaded here, in a file of its own: a loaded font stays
// registered for the rest of the file, and the other study tests measure
// contrast with the test font's solid glyphs.

/// A phone's width, as the study screen's tests use.
const _phoneWidth = 390.0;

Card _card(String front) => Card(
  id: const CardId('c'),
  deckId: const DeckId('d'),
  front: [TextContent(front)],
  back: const [TextContent('answer')],
  cardKey: CardKey.fromFront(front),
  source: CardSource.manual,
  createdAt: DateTime.utc(2026, 10, 16),
  updatedAt: DateTime.utc(2026, 10, 16),
);

/// The widest word of [text] in the question's style at [size].
double _widest(String text, double size) => text
    .split(' ')
    .map(
      (word) => (TextPainter(
        text: TextSpan(
          text: word,
          style: AppType.question.copyWith(fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).width,
    )
    .reduce((a, b) => a > b ? a : b);

/// Schedules every review one day out, at once.
class _InstantScheduler implements Scheduler {
  @override
  Future<CardState?> fold(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

  @override
  Future<List<CardState>> history(List<ReviewRow> reviews) =>
      throw UnimplementedError('sessions do not fold');

  @override
  Future<double> retrievability(CardState state, DateTime at) =>
      throw UnimplementedError('sessions read no recall');

  @override
  Future<CardState> review(
    CardState? state,
    Answer answer,
    DateTime at, {
    required FuzzFactor fuzz,
  }) async => CardState(
    stability: 1,
    difficulty: 5,
    lastReview: at,
    due: at.add(const Duration(days: 1)),
  );
}

/// The text of the answer half's paragraph inside [card] that holds [text].
RenderParagraph _paragraph(WidgetTester tester, Finder card, String text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: card, matching: find.textContaining(text)).last,
    );

void main() {
  setUpAll(() async {
    // Pretendard's own widths; the test font draws every glyph an em wide.
    final pretendard = FontLoader(appFontFamily);
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      pretendard.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Pretendard-$weight.otf').readAsBytesSync(),
          ),
        ),
      );
    }
    await pretendard.load();
  });

  testWidgets(
    'a question shrinks until its widest word fits, breaks only between words above the floor, and sits centred on the current card',
    (tester) async {
      tester.view.physicalSize = const Size(_phoneWidth, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final front in [
        'meticulous',
        'antidisestablishmentarianism',
        'pneumonoultramicroscopicsilicovolcanoconiosis',
        'once in a blue moon',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: lightTheme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: StudyStyle.cardMargin,
                ),
                child: Center(
                  child: CurrentCard(
                    key: ValueKey(front),
                    card: _card(front),
                    onAnswer: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        // The card's face, without the answer buttons under it.
        final card = tester.getRect(
          find
              .descendant(
                of: find.byType(CurrentCard),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(card.width, _phoneWidth - 2 * StudyStyle.cardMargin);
        final text = find.text(front);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final size = paragraph.text.style!.fontSize!;
        final width = card.width - StudyStyle.cardPadding * 2;

        expect(size, lessThanOrEqualTo(AppType.question.fontSize!));
        expect(size, greaterThanOrEqualTo(AppType.questionFloor));
        if (_widest(front, AppType.questionFloor) <= width) {
          // The widest word fits at this size, and every word sits on one
          // line.
          expect(_widest(front, size), lessThanOrEqualTo(width), reason: front);
          var start = 0;
          for (final word in front.split(' ')) {
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: start,
                extentOffset: start + word.length,
              ),
            );
            expect(
              boxes.map((box) => box.top).toSet(),
              hasLength(1),
              reason: '"$word" of "$front" breaks across lines',
            );
            start += word.length + 1;
          }
        } else {
          // Past the floor a word may break, at the floor's size.
          expect(size, AppType.questionFloor, reason: front);
        }
        // Centred on the card, across and down.
        expect(
          tester.getCenter(text).dx,
          closeTo(card.center.dx, 1),
          reason: front,
        );
        expect(
          tester.getCenter(text).dy,
          closeTo(card.center.dy, 1),
          reason: front,
        );
      }
      // Control: "antidisestablishmentarianism" lands between the floor and
      // the full size, and "pneumonoultramicroscopicsilicovolcanoconiosis"
      // does not fit even at the floor, so both branches above ran.
      final width =
          _phoneWidth - 2 * StudyStyle.cardMargin - StudyStyle.cardPadding * 2;
      expect(
        fittedFontSize(
          'antidisestablishmentarianism',
          style: AppType.question,
          minFontSize: AppType.questionFloor,
          width: width,
          textScaler: TextScaler.noScaling,
          textDirection: TextDirection.ltr,
        ),
        allOf(
          greaterThan(AppType.questionFloor),
          lessThan(AppType.question.fontSize!),
        ),
      );
      expect(
        _widest(
          'pneumonoultramicroscopicsilicovolcanoconiosis',
          AppType.questionFloor,
        ),
        greaterThan(width),
      );
    },
  );

  testWidgets(
    'a long answer shows whole at the answer size on the previous card, on a 390 by 844 phone at the default text scale',
    (tester) async {
      const answer = '(결과·수익 등을) 내다, 산출하다; 양도하다';
      // An iPhone of that size: its status bar and home indicator.
      tester.view.physicalSize = const Size(_phoneWidth, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final decks = DeckRepository(
        db,
        clock: () => DateTime.utc(2026, 9, 1),
        newId: () => 'id${ids++}',
      );
      final deck = (await tester.runAsync(() async {
        final deck = await decks.createDeck('English');
        await decks.addCard(
          deck.id,
          front: const [TextContent('yield')],
          back: const [TextContent(answer)],
        );
        return deck;
      }))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckRepositoryProvider.overrideWithValue(decks),
            studyRepositoryProvider.overrideWithValue(
              StudyRepository(db, newId: () => 'review${ids++}'),
            ),
            schedulerProvider.overrideWithValue(_InstantScheduler()),
            studyClockProvider.overrideWithValue(
              () => DateTime.utc(2026, 10, 14, 9),
            ),
            studyZoneProvider.overrideWithValue((_) => Duration.zero),
            studyRandomProvider.overrideWithValue((_) => FirstDraw()),
          ],
          child: MaterialApp(
            theme: lightTheme,
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: StudyScreen(decks: DeckSelection(deck.id)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Answered "모른다", the card is shown again at once, under itself as
      // the previous card, which shows the answer whole, uncut.
      await tester.tap(find.widgetWithText(TextButton, '모른다'));
      await tester.pumpAndSettle();
      final previous = find.byType(PreviousCardView);
      expect(previous, findsOneWidget);
      final kept = _paragraph(tester, previous, '양도하다');
      expect(kept.text.style!.fontSize, AppType.answer.fontSize);
      expect(kept.text.toPlainText(), answer);
      expect(kept.didExceedMaxLines, isFalse);
      // Control: it wraps, so the room the card gives it is what fits it.
      expect(
        kept.size.height,
        greaterThan(AppType.answer.fontSize! * AppType.answer.height!),
      );
      expect(
        tester.getSize(previous),
        tester.getSize(
          find
              .descendant(
                of: find.byType(CurrentCard),
                matching: find.byType(GestureDetector),
              )
              .first,
        ),
      );
    },
  );
}
