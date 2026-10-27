import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

const _ink = Color(0xFF1F2A44);
const _surface = Color(0xFFFFFFFF);
const _tint = Color(0xFFE0E7FF);

/// [child] on a white surface across the screen.
Future<void> _pump(WidgetTester tester, Widget child, {Color? ground}) =>
    tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ground == null
            ? child
            : ColoredBox(
                color: ground,
                child: Align(alignment: Alignment.topLeft, child: child),
              ),
      ),
    );

Matcher get _fails => throwsA(isA<TestFailure>());

void main() {
  testWidgets('ink on the surface passes, and the same text in the surface '
      'colour fails', (tester) async {
    await _pump(
      tester,
      const Text('Quiet', style: TextStyle(color: _ink)),
      ground: _surface,
    );
    expectScreenTextReadable(tester);

    await _pump(
      tester,
      const Text('Quiet', style: TextStyle(color: _surface)),
      ground: _surface,
    );
    expect(() => expectScreenTextReadable(tester), _fails);
  });

  testWidgets('a text with no opaque fill under it fails', (tester) async {
    await _pump(tester, const Text('Bare', style: TextStyle(color: _ink)));
    expect(() => expectScreenTextReadable(tester), _fails);
  });

  testWidgets('a text over a photo fails unless it is named, and a name that '
      'is not over one fails', (tester) async {
    final photo = (await tester.runAsync(
      () => createTestImage(width: 40, height: 40),
    ))!;
    await _pump(
      tester,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              RawImage(image: photo, width: 200, height: 100),
              const Text('Caption', style: TextStyle(color: _surface)),
            ],
          ),
          const Text('Plain', style: TextStyle(color: _ink)),
        ],
      ),
      ground: _surface,
    );
    expect(() => expectScreenTextReadable(tester), _fails);
    // Control: the same text named.
    expectScreenTextReadable(tester, overPhoto: {'Caption'});
    expect(
      () => expectScreenTextReadable(tester, overPhoto: {'Caption', 'Other'}),
      _fails,
    );
  });

  testWidgets("a disabled control's text is left out, and the same text "
      'enabled fails', (tester) async {
    Widget control({required bool enabled}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ready', style: TextStyle(color: _ink)),
        Semantics(
          enabled: enabled,
          child: const Text('Off', style: TextStyle(color: Color(0x611F2A44))),
        ),
      ],
    );
    await _pump(tester, control(enabled: false), ground: _surface);
    expectScreenTextReadable(tester);

    await _pump(tester, control(enabled: true), ground: _surface);
    expect(() => expectScreenTextReadable(tester), _fails);
  });

  testWidgets('a span in the colour of its own fill is a mask and left out, '
      'and a span with a fill is measured on that fill', (tester) async {
    Widget line(TextSpan blank) => Text.rich(
      TextSpan(
        style: const TextStyle(color: _ink),
        children: [
          const TextSpan(text: 'Capital: '),
          blank,
        ],
      ),
    );
    await _pump(
      tester,
      line(
        const TextSpan(
          text: ' Paris ',
          style: TextStyle(color: _tint, backgroundColor: _tint),
        ),
      ),
      ground: _surface,
    );
    expectScreenTextReadable(tester);

    // Control: in the tint on the surface, with no fill, it is read.
    await _pump(
      tester,
      line(
        const TextSpan(
          text: ' Paris ',
          style: TextStyle(color: _tint),
        ),
      ),
      ground: _surface,
    );
    expect(() => expectScreenTextReadable(tester), _fails);

    // Ink on a dark fill fails on the fill, though it passes on the surface.
    await _pump(
      tester,
      line(
        const TextSpan(
          text: ' Paris ',
          style: TextStyle(backgroundColor: Color(0xFF3A4566)),
        ),
      ),
      ground: _surface,
    );
    expect(() => expectScreenTextReadable(tester), _fails);
  });

  testWidgets('a fully transparent span, an empty blank, is a mask and left '
      'out, and the same span faintly drawn fails', (tester) async {
    Widget line(Color colour) => Text.rich(
      TextSpan(
        style: const TextStyle(color: _ink),
        children: [
          const TextSpan(text: 'Capital: '),
          TextSpan(
            text: ' Paris ',
            style: TextStyle(
              color: colour,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
    await _pump(tester, line(_tint.withValues(alpha: 0)), ground: _surface);
    expectScreenTextReadable(tester);

    // Control: the same span at a faint alpha is text, and unreadable.
    await _pump(tester, line(_tint.withValues(alpha: 0.3)), ground: _surface);
    expect(() => expectScreenTextReadable(tester), _fails);
  });

  testWidgets('a known failure must still fail, and the rest are still '
      'checked', (tester) async {
    Widget texts(Color second) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Label', style: TextStyle(color: _tint)),
        Text('Other', style: TextStyle(color: second)),
      ],
    );
    await _pump(tester, texts(_ink), ground: _surface);
    expectScreenTextReadable(tester, failing: {'Label'});
    expect(
      () => expectScreenTextReadable(tester, failing: {'Label', 'Other'}),
      _fails,
      reason: 'Other passes, so it is not a known failure',
    );

    await _pump(tester, texts(_surface), ground: _surface);
    expect(
      () => expectScreenTextReadable(tester, failing: {'Label'}),
      _fails,
      reason: 'Other is checked',
    );
  });

  testWidgets('a text scrolled off screen is left out', (tester) async {
    await _pump(
      tester,
      SizedBox(
        height: 600,
        child: const SingleChildScrollView(
          child: Column(
            children: [
              Text('Top', style: TextStyle(color: _ink)),
              SizedBox(height: 2000),
              Text('Below', style: TextStyle(color: _surface)),
            ],
          ),
        ),
      ),
      ground: _surface,
    );
    expect(find.text('Below', skipOffstage: false), findsOneWidget);
    expectScreenTextReadable(tester);

    // Control: scrolled into view, it fails.
    await tester.scrollUntilVisible(find.text('Below'), 500);
    expect(() => expectScreenTextReadable(tester), _fails);
  });
}
