import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/app_button.dart';
import 'package:smartman/design/app_sheet.dart';
import 'package:smartman/design/theme.dart';

import 'harness.dart';

/// The word joiner `keepWords` puts between a word's characters.
const _wordJoiner = '\u2060';

/// A [Text] whose text, word joiners aside, is [text].
Finder _text(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data?.replaceAll(_wordJoiner, '') == text,
);

/// Where each line of [text]'s paragraph ends, as offsets into its text with
/// the word joiners in, and that text.
(List<int>, String) _lineEnds(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: _text(text), matching: find.byType(RichText)),
  );
  final plain = paragraph.text.toPlainText();
  // The paragraph's own text laid out at its width, to read its lines.
  final lines = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  addTearDown(lines.dispose);
  final ends = <int>[];
  for (var offset = 0; offset < plain.length;) {
    offset = lines.getLineBoundary(TextPosition(offset: offset)).end;
    ends.add(offset);
  }
  return (ends, plain);
}

/// A button that opens [open] and keeps what it resolved to in [results].
Widget _opener(
  Future<Object?> Function(BuildContext context) open,
  List<Object?> results,
) => Builder(
  builder: (context) => AppButton(
    label: 'open',
    onPressed: () async => results.add(await open(context)),
  ),
);

/// The sheet with a body, content and two actions, the primary last.
Future<Object?> _openSheet(BuildContext context) => showAppSheet<String>(
  context,
  builder: (context) => AppSheet(
    title: 'New deck',
    body: 'Name it after what you study.',
    content: const TextField(),
    actions: [
      AppButton(
        label: 'Later',
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.cta,
        onPressed: () => Navigator.of(context).pop('later'),
      ),
      AppButton(
        label: 'Create',
        size: AppButtonSize.cta,
        onPressed: () => Navigator.of(context).pop('create'),
      ),
    ],
  ),
);

void main() {
  for (final MapEntry(key: mode, value: colors) in themeModes.entries) {
    testWidgets(
      'in ${mode.name} the sheet stacks its handle, title, body, content and actions, primary last and full width',
      (tester) async {
        final results = <Object?>[];
        await pumpComponent(
          tester,
          _opener(_openSheet, results),
          themeMode: mode,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final sheet = tester.getRect(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Material),
              )
              .first,
        );
        final title = tester.getRect(_text('New deck'));
        final body = tester.getRect(_text('Name it after what you study.'));
        final content = tester.getRect(find.byType(TextField));
        final later = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Later'),
        );
        final create = tester.getRect(
          find.widgetWithText(FilledButton, 'Create'),
        );
        expect(title.bottom, lessThanOrEqualTo(body.top));
        expect(body.bottom, lessThanOrEqualTo(content.top));
        expect(content.bottom, lessThanOrEqualTo(later.top));
        expect(later.bottom, lessThanOrEqualTo(create.top));
        expect(create.width, sheet.width - AppSpace.gutter * 2);
        expect(create.height, AppSize.cta);
        expect(
          tester.getSemantics(_text('New deck')),
          isSemantics(isHeader: true, label: 'New deck'),
        );
        final shape = tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .shape;
        expect(
          shape,
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
          ),
        );
        expect(
          tester
              .widget<Material>(
                find
                    .descendant(
                      of: find.byType(BottomSheet),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color,
          colors.surface,
        );
        await meetsGuidelines(tester);

        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        expect(results, ['create']);
      },
    );
  }

  testWidgets('a dismissed sheet resolves to null', (tester) async {
    final results = <Object?>[];
    await pumpComponent(tester, _opener(_openSheet, results));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(results, [null]);
  });

  testWidgets('the actions stay above the keyboard', (tester) async {
    final results = <Object?>[];
    await pumpComponent(tester, _opener(_openSheet, results));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final before = tester.getRect(find.text('Create'));
    expect(before.bottom, lessThan(screen.height));

    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final after = tester.getRect(find.text('Create'));
    expect(after.bottom, lessThanOrEqualTo(screen.height - 300));
    expect(after.top, lessThan(before.top));
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
      reduceMotion
          ? 'under reduce motion the sheet appears at once'
          : 'the sheet slides up with the platform motion',
      (tester) async {
        final results = <Object?>[];
        await pumpComponent(
          tester,
          _opener(_openSheet, results),
          disableAnimations: reduceMotion,
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final early = tester.getRect(_text('New deck')).top;
        await tester.pumpAndSettle();
        final settled = tester.getRect(_text('New deck')).top;

        if (reduceMotion) {
          expect(early, settled);
        } else {
          expect(early, greaterThan(settled));
        }
      },
    );
  }

  group('confirm', () {
    for (final MapEntry(key: mode, value: colors) in themeModes.entries) {
      testWidgets(
        'in ${mode.name} it states the consequence beside a red final button',
        (tester) async {
          final results = <Object?>[];
          await pumpComponent(
            tester,
            _opener(
              (context) => showAppConfirm(
                context,
                title: 'Delete "French"?',
                consequence: 'Its 3 cards will be deleted too.',
                confirmLabel: 'Delete',
              ),
              results,
            ),
            themeMode: mode,
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(_text('Its 3 cards will be deleted too.'), findsOneWidget);
          expect(
            tester
                .widget<Material>(
                  find
                      .ancestor(
                        of: find.text('Delete'),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .color,
            colors.dontKnowText,
          );
          expect(
            tester.getRect(find.text('Cancel')).top,
            lessThan(tester.getRect(find.text('Delete')).top),
          );
          await meetsGuidelines(tester);
        },
      );
    }

    testWidgets(
      'its cancel takes the label it is given, and resolves to false',
      (tester) async {
        final results = <Object?>[];
        await pumpComponent(
          tester,
          _opener(
            (context) => showAppConfirm(
              context,
              title: 'Discard this card?',
              consequence: "What you typed won't be saved.",
              confirmLabel: 'Discard',
              cancelLabel: 'Keep writing',
            ),
            results,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsNothing);

        await tester.tap(find.text('Keep writing'));
        await tester.pumpAndSettle();
        expect(results, [false]);
      },
    );

    for (final (action, expected) in [
      ('Delete', true),
      ('Cancel', false),
      (null, false),
    ]) {
      testWidgets('${action ?? 'dismissing'} resolves to $expected', (
        tester,
      ) async {
        final results = <Object?>[];
        await pumpComponent(
          tester,
          _opener(
            (context) => showAppConfirm(
              context,
              title: 'Delete this card?',
              consequence: 'Its study history is deleted with it.',
              confirmLabel: 'Delete',
            ),
            results,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        if (action == null) {
          await tester.tapAt(const Offset(20, 20));
        } else {
          await tester.tap(find.text(action));
        }
        await tester.pumpAndSettle();

        expect(results, [expected]);
      });
    }
  });

  testWidgets(
    'on a 390 wide phone a Korean title and body break only between words, read as written, and a word wider than the line still wraps',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const title = '동기화되지 않은 변경이 있어요 로그아웃할까요';
      const body = '동기화되지 않은 변경은 로그아웃하면 이 기기에서 지워지고, 다른 기기에서도 볼 수 없어요.';
      // The control: one word, so it can break only inside itself.
      const word = '동기화되지않은변경은로그아웃하면이기기에서지워지고다른기기에서도볼수없어요';
      for (final (sheetTitle, sheetBody) in [(title, body), ('제목', word)]) {
        // A fresh app, so the first sheet is not under the second.
        await tester.pumpWidget(const SizedBox());
        await pumpComponent(
          tester,
          _opener(
            (context) => showAppSheet<void>(
              context,
              builder: (context) =>
                  AppSheet(title: sheetTitle, body: sheetBody),
            ),
            [],
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        if (sheetBody == word) {
          final (ends, _) = _lineEnds(tester, word);
          expect(ends.length, greaterThan(1), reason: 'the control wraps');
          continue;
        }
        for (final text in [title, body]) {
          final (ends, plain) = _lineEnds(tester, text);
          // The text wraps at this width, so where it breaks is tested.
          expect(ends.length, greaterThan(1), reason: text);
          for (final end in ends.take(ends.length - 1)) {
            expect(
              plain[end - 1] == ' ' || plain[end] == ' ',
              isTrue,
              reason: 'a break at $end in "$text"',
            );
          }
          // A screen reader reads it as written, without the joiners.
          expect(find.bySemanticsLabel(text), findsOneWidget);
        }
      }
    },
  );
}
