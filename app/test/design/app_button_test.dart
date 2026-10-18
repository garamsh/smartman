import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/app_button.dart';
import 'package:smartman/design/theme.dart';

import 'harness.dart';

/// The fill the button labelled [label] is drawn with.
Color? _fill(WidgetTester tester, String label) {
  final material = tester.widget<Material>(
    find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
  );
  return material.color;
}

void main() {
  for (final MapEntry(key: mode, value: colors) in themeModes.entries) {
    testWidgets(
      'in ${mode.name} each variant draws its fill and meets the guidelines',
      (tester) async {
        await pumpComponent(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s8,
            children: [
              for (final variant in AppButtonVariant.values)
                AppButton(
                  label: variant.name,
                  variant: variant,
                  onPressed: () {},
                ),
            ],
          ),
          themeMode: mode,
        );

        expect(_fill(tester, 'primary'), colors.ink);
        expect(_fill(tester, 'onHero'), colors.onHero);
        // The primary fill inverts in the dark theme, and its label with it.
        expect(
          tester
              .widget<DefaultTextStyle>(
                find
                    .ancestor(
                      of: find.text('primary'),
                      matching: find.byType(DefaultTextStyle),
                    )
                    .first,
              )
              .style
              .color,
          colors.onPrimary,
        );
        expect(_fill(tester, 'destructiveFinal'), colors.dontKnowText);
        expect(_fill(tester, 'secondary'), colors.surface);
        expect(
          tester
              .widget<DefaultTextStyle>(
                find
                    .ancestor(
                      of: find.text('destructive'),
                      matching: find.byType(DefaultTextStyle),
                    )
                    .first,
              )
              .style
              .color,
          colors.dontKnowText,
        );
        await meetsGuidelines(tester);
      },
    );
  }

  testWidgets(
    'a call to action is taller than a button, and a quiet one is a tap target',
    (tester) async {
      await pumpComponent(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(label: 'cta', size: AppButtonSize.cta, onPressed: () {}),
            AppButton(label: 'regular', onPressed: () {}),
            AppButton(
              label: 'text',
              variant: AppButtonVariant.text,
              onPressed: () {},
            ),
          ],
        ),
      );

      double height(String label) => tester
          .getSize(
            find
                .ancestor(of: find.text(label), matching: find.byType(Material))
                .first,
          )
          .height;
      expect(height('cta'), AppSize.cta);
      expect(height('regular'), AppSize.button);
      expect(height('text'), AppSize.tapTarget);
    },
  );

  testWidgets('a press calls back, and a disabled button cannot be pressed', (
    tester,
  ) async {
    var presses = 0;
    await pumpComponent(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(label: 'enabled', onPressed: () => presses++),
          const AppButton(label: 'disabled', onPressed: null),
        ],
      ),
    );

    await tester.tap(find.text('enabled'));
    expect(presses, 1);
    await tester.tap(find.text('disabled'));
    expect(presses, 1);
    expect(
      tester.getSemantics(find.text('disabled')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
  });

  testWidgets('a button gives pressed feedback while held', (tester) async {
    await pumpComponent(tester, AppButton(label: 'hold', onPressed: () {}));
    final ink = find.byType(InkWell);
    final idle = tester.widget<InkWell>(ink).overlayColor?.resolve({});
    final pressed = tester.widget<InkWell>(ink).overlayColor?.resolve({
      WidgetState.pressed,
    });

    expect(pressed, isNotNull);
    expect(pressed, isNot(idle));
  });

  testWidgets(
    'while loading it shows progress read as its label, and cannot be pressed again',
    (tester) async {
      var presses = 0;
      await pumpComponent(
        tester,
        AppButton(
          label: 'Save',
          loadingLabel: 'Saving',
          loading: true,
          onPressed: () => presses++,
        ),
        settle: false,
      );

      expect(find.text('Save'), findsNothing);
      expect(find.bySemanticsLabel('Saving'), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      expect(presses, 0);
      // Control: the same button, not loading, is pressed.
      await pumpComponent(
        tester,
        AppButton(label: 'Save', onPressed: () => presses++),
      );
      await tester.tap(find.byType(AppButton));
      expect(presses, 1);
    },
  );

  group('haptics', () {
    late List<String> haptics;
    setUp(() {
      haptics = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Future<void> pressBoth(WidgetTester tester) async {
      await pumpComponent(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(label: 'confirm', onPressed: () {}),
            AppButton(
              label: 'other',
              variant: AppButtonVariant.secondary,
              onPressed: () {},
            ),
          ],
        ),
      );
      await tester.tap(find.text('other'));
      await tester.tap(find.text('confirm'));
    }

    testWidgets(
      'on iOS a filled button gives a light haptic, and an outlined one does not',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await pressBoth(tester);
        debugDefaultTargetPlatformOverride = null;

        expect(haptics, ['HapticFeedbackType.lightImpact']);
      },
    );

    testWidgets('on Android no button gives a haptic', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pressBoth(tester);
      debugDefaultTargetPlatformOverride = null;

      expect(haptics, isEmpty);
    });
  });
}
