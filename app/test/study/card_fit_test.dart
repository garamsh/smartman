import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/l10n/app_localizations.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/shared/ui/card_text.dart';
import 'package:smartman/study/src/current_card.dart';
import 'package:smartman/study/src/study_style.dart';

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
    'a question shrinks until its widest word fits, breaks only between words above the floor, and sits centred in its half',
    (tester) async {
      tester.view.physicalSize = const Size(_phoneWidth, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final front in [
        'meticulous',
        'incomprehensibility',
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
        final width = (card.width - 1) / 2 - StudyStyle.cardPadding * 2;

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
        // Centred in the question's half, across and down.
        final half = Rect.fromLTRB(
          card.left,
          card.top,
          card.left + card.width / 2,
          card.bottom,
        );
        expect(
          tester.getCenter(text).dx,
          closeTo(half.center.dx, 1),
          reason: front,
        );
        expect(
          tester.getCenter(text).dy,
          closeTo(half.center.dy, 1),
          reason: front,
        );
      }
      // Control: "meticulous" lands between the floor and the full size, and
      // "incomprehensibility" does not fit even at the floor, so both
      // branches above ran.
      final width =
          (_phoneWidth - 2 * StudyStyle.cardMargin - 1) / 2 -
          StudyStyle.cardPadding * 2;
      expect(
        fittedFontSize(
          'meticulous',
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
        _widest('incomprehensibility', AppType.questionFloor),
        greaterThan(width),
      );
    },
  );
}
