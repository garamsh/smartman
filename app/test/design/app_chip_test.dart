import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartman/design/app_chip.dart';
import 'package:smartman/design/theme.dart';

import 'harness.dart';

/// The Material the chip labelled [label] is drawn on.
Material _material(WidgetTester tester, String label) =>
    tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );

Finder _check(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
  matching: find.byIcon(LucideIcons.check),
);

void main() {
  for (final MapEntry(key: mode, value: colors) in themeModes.entries) {
    testWidgets(
      'in ${mode.name} a chosen chip takes the navy fill and a check, an '
      'unchosen one an outline, each read as selected or not, and both meet '
      'the guidelines',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpComponent(
          tester,
          Wrap(
            spacing: AppSpace.s8,
            children: [
              AppChip(label: 'on', selected: true, onPressed: () {}),
              // The tone yields to the choice.
              AppChip(
                label: 'off',
                tone: AppChipTone.brand,
                selected: false,
                onPressed: () {},
              ),
            ],
          ),
          themeMode: mode,
        );

        final on = _material(tester, 'on');
        expect(on.color, colors.ink);
        expect(on.textStyle?.color, colors.onPrimary);
        expect(_check('on'), findsOneWidget);

        final off = _material(tester, 'off');
        expect(off.color, colors.surface);
        expect((off.shape! as StadiumBorder).side.color, colors.outline);
        expect(off.textStyle?.color, colors.ink);
        expect(_check('off'), findsNothing);

        expect(
          tester.getSemantics(find.text('on')),
          matchesSemantics(
            label: 'on',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
            hasSelectedState: true,
            isSelected: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('off')),
          matchesSemantics(
            label: 'off',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
            hasSelectedState: true,
          ),
        );
        await meetsGuidelines(tester);
        handle.dispose();
      },
    );
  }
}
