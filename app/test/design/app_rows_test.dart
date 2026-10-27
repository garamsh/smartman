import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/app_chip.dart';
import 'package:smartman/design/app_list_row.dart';
import 'package:smartman/design/app_section_label.dart';
import 'package:smartman/design/theme.dart';

import '../contrast.dart';
import '../word_breaks.dart';
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
        expectScreenTextReadable(tester);
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
            .renderObject<RenderParagraph>(
              find.descendant(
                of: shownText(text),
                matching: find.byType(RichText),
              ),
            )
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
        expectScreenTextReadable(tester);
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
            const AppChip(label: 'Today 3', tone: AppChipTone.brand),
            const AppChip(label: 'Public'),
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
      expect(
        tester
            .widget<DecoratedBox>(
              find
                  .ancestor(
                    of: find.text('Public'),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration,
        ShapeDecoration(
          color: colors.surface,
          shape: StadiumBorder(side: BorderSide(color: colors.outline)),
        ),
      );
      await meetsGuidelines(tester);
      expectScreenTextReadable(tester);
    });
  }

  for (final (name, group) in [
    (
      'a group',
      (List<Widget> rows) =>
          SingleChildScrollView(child: AppGroup(children: rows)),
    ),
    (
      'a sliver group',
      (List<Widget> rows) =>
          CustomScrollView(slivers: [SliverAppGroup(children: rows)]),
    ),
  ]) {
    testWidgets(
      'in $name the rows share one surface rounded at its ends, with no surface or gap of their own, split by a hairline under all but the first, where a row alone keeps its own',
      (tester) async {
        final colors = themeModes[ThemeMode.light]!;
        // Control: a row alone is its own rounded surface over the row gap.
        await pumpComponent(tester, AppListRow(title: 'Alone', onTap: () {}));
        final alone = tester.widget<Material>(
          find
              .ancestor(of: find.text('Alone'), matching: find.byType(Material))
              .first,
        );
        expect(alone.color, colors.surface);
        expect(alone.borderRadius, BorderRadius.circular(AppRadius.row));

        await pumpComponent(
          tester,
          group([
            AppListRow(title: 'First', onTap: () {}),
            AppListRow(title: 'Second', onTap: () {}),
            const AppRowSurface(child: Text('Third')),
          ]),
        );
        for (final (index, row) in ['First', 'Second', 'Third'].indexed) {
          final materials = tester
              .widgetList<Material>(
                find.ancestor(
                  of: find.text(row),
                  matching: find.byType(Material),
                ),
              )
              .toList();
          // The row's own is see-through; the group's share is the surface.
          expect(materials[0].type, MaterialType.transparency, reason: row);
          expect(materials[1].color, colors.surface, reason: row);
          expect(
            materials[1].borderRadius,
            BorderRadius.vertical(
              top: index == 0
                  ? const Radius.circular(AppRadius.group)
                  : Radius.zero,
              bottom: index == 2
                  ? const Radius.circular(AppRadius.group)
                  : Radius.zero,
            ),
            reason: row,
          );
        }
        final dividers = tester.widgetList<Divider>(find.byType(Divider));
        expect(dividers, hasLength(2));
        expect({for (final line in dividers) line.color}, {colors.hairline});
        final lines = [
          for (final element in find.byType(Divider).evaluate())
            tester.getRect(find.byWidget(element.widget)).center.dy,
        ];
        double top(String row) => tester.getRect(find.text(row)).top;
        double bottom(String row) => tester.getRect(find.text(row)).bottom;
        expect(lines[0], inExclusiveRange(bottom('First'), top('Second')));
        expect(lines[1], inExclusiveRange(bottom('Second'), top('Third')));
      },
    );
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
      await tester.longPress(shownText('3 cards'));

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

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'on a 390 wide phone at text scale $scale a row\'s Korean subtitle breaks only between words and is read as written, and a word wider than the line still wraps',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const subtitle = '계정을 삭제하면 서버와 이 기기에 있는 카드와 기록이 모두 지워져요. 되돌릴 수 없어요.';
        // The control: one word, so it can break only inside itself.
        const word = '계정을삭제하면서버와이기기에있는카드와기록이모두지워져요되돌릴수없어요';
        await pumpComponent(
          tester,
          Column(
            children: [
              AppListRow(title: '계정 삭제', subtitle: subtitle, onTap: () {}),
              AppListRow(title: '제목', subtitle: word, onTap: () {}),
            ],
          ),
        );

        expectBreaksBetweenWords(tester, subtitle);
        expectWrapsInsideWord(tester, word);
        // A screen reader reads the row's title and subtitle as written.
        expect(
          tester.getSemantics(find.text('계정 삭제')),
          isSemantics(label: '계정 삭제\n$subtitle', hasTapAction: true),
        );
        semantics.dispose();
      },
    );
  }
}
