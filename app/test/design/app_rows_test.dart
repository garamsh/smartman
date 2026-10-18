import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/app_chip.dart';
import 'package:smartman/design/app_list_row.dart';
import 'package:smartman/design/app_section_label.dart';

import 'harness.dart';

/// The fill of the nearest [Material] around [finder].
Color? _fill(WidgetTester tester, Finder finder) => tester
    .widget<Material>(
      find.ancestor(of: finder, matching: find.byType(Material)).first,
    )
    .color;

void main() {
  for (final MapEntry(key: mode, value: colors) in themeModes.entries) {
    testWidgets(
      'in ${mode.name} a row is a surface on the ground, and on a sheet takes the ground',
      (tester) async {
        await pumpComponent(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppSectionLabel('My decks 2'),
              AppListRow(title: 'French', subtitle: '3 cards', onTap: () {}),
              AppListRow(title: 'German', onSheet: true, onTap: () {}),
            ],
          ),
          themeMode: mode,
        );

        expect(_fill(tester, find.text('French')), colors.surface);
        expect(_fill(tester, find.text('German')), colors.ground);
        expect(
          tester.getSemantics(find.text('My decks 2')),
          isSemantics(isHeader: true, label: 'My decks 2'),
        );
        await meetsGuidelines(tester);
      },
    );

    testWidgets(
      'in ${mode.name} a destructive row draws its title and icon in red, and a plain row in ink',
      (tester) async {
        await pumpComponent(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppListRow(
                title: 'Delete account',
                subtitle: 'This removes everything.',
                leading: const Icon(Icons.delete_forever_outlined),
                destructive: true,
                onTap: () {},
              ),
              AppListRow(
                title: 'Sign out',
                leading: const Icon(Icons.logout),
                onTap: () {},
              ),
            ],
          ),
          themeMode: mode,
        );

        Color? textColor(String text) => tester
            .renderObject<RenderParagraph>(find.text(text))
            .text
            .style
            ?.color;
        Color? iconColor(IconData icon) => tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.byIcon(icon),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style
            ?.color;
        expect(textColor('Delete account'), colors.dontKnowText);
        expect(iconColor(Icons.delete_forever_outlined), colors.dontKnowText);
        expect(textColor('This removes everything.'), colors.muted);
        expect(textColor('Sign out'), isNot(colors.dontKnowText));
        expect(iconColor(Icons.logout), isNot(colors.dontKnowText));
        await meetsGuidelines(tester);
      },
    );

    testWidgets('in ${mode.name} a chip is fully rounded, in its tone', (
      tester,
    ) async {
      await pumpComponent(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppChip(
              label: 'Today 3',
              kind: AppChipStatus(tone: AppChipTone.brand),
            ),
            AppChip(
              label: 'Skip',
              kind: AppChipAction(icon: Icons.expand_more, onPressed: () {}),
            ),
          ],
        ),
        themeMode: mode,
      );

      final label = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Today 3'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        label.decoration,
        ShapeDecoration(
          color: colors.brandTint,
          shape: StadiumBorder(side: BorderSide(color: colors.brandTint)),
        ),
      );
      expect(_fill(tester, find.text('Skip')), colors.surface);
      await meetsGuidelines(tester);
    });
  }

  testWidgets(
    'a row reads as one node, answers a tap and a long press, and states selection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final events = <String>[];
      await pumpComponent(
        tester,
        AppListRow(
          title: 'French',
          subtitle: '3 cards',
          selected: true,
          onTap: () => events.add('tap'),
          onLongPress: () => events.add('long'),
        ),
      );

      await tester.tap(find.text('French'));
      await tester.longPress(find.text('3 cards'));

      expect(events, ['tap', 'long']);
      expect(
        tester.getSemantics(find.text('French')),
        isSemantics(
          label: 'French\n3 cards',
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a chip with an action is a button with a full tap target, and one without is a label',
    (tester) async {
      var presses = 0;
      await pumpComponent(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppChip(label: 'Today 3'),
            AppChip(
              label: 'Skip',
              kind: AppChipAction(onPressed: () => presses++),
            ),
          ],
        ),
      );

      await tester.tap(find.text('Skip'));
      expect(presses, 1);
      expect(
        tester.getSemantics(find.text('Skip')),
        isSemantics(isButton: true, hasTapAction: true, label: 'Skip'),
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSemantics(find.text('Today 3')),
        isNot(isSemantics(isButton: true)),
      );
    },
  );
}
