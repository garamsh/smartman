import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/shared/theme.dart';
import 'package:smartman/shared/ui/app_button.dart';
import 'package:smartman/shared/ui/app_sheet.dart';

import 'harness.dart';

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
        final title = tester.getRect(find.text('New deck'));
        final body = tester.getRect(find.text('Name it after what you study.'));
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
          tester.getSemantics(find.text('New deck')),
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
        final early = tester.getRect(find.text('New deck')).top;
        await tester.pumpAndSettle();
        final settled = tester.getRect(find.text('New deck')).top;

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

          expect(find.text('Its 3 cards will be deleted too.'), findsOneWidget);
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
}
