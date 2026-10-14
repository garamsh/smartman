import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/rust/frb_generated.dart';

/// The engine's own reference values, written by `engine/tests/fixtures/generate.py`.
const _fixtures = '../engine/tests/fixtures/reference.json';

/// The relative tolerance `engine/tests/reference.rs` holds the engine to.
const _relativeTolerance = 1e-9;

Matcher _closeTo(num expected) =>
    closeTo(expected, (expected * _relativeTolerance).abs());

void main() {
  setUpAll(() async => RustLib.init());

  test(
    'reviewing persisted state parts returns the reference step of the engine',
    () async {
      final fixtures = jsonDecode(
        File(_fixtures).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(fixtures['generator'], 'py-fsrs 6.3.2');
      final reviews =
          ((fixtures['sequences'] as List<dynamic>).singleWhere(
                (sequence) =>
                    (sequence as Map<String, dynamic>)['name'] ==
                    'two-button-session',
              ) as Map<String, dynamic>)['reviews']
              as List<dynamic>;
      final previous = reviews[2] as Map<String, dynamic>;
      final step = reviews[3] as Map<String, dynamic>;
      // Rating 3 is the "Know" button.
      expect(step['rating'], 3);

      final state = MemoryStateParts(
        stability: previous['stability'] as double,
        difficulty: previous['difficulty'] as double,
        lastReview: previous['at'] as int,
      );
      final at = step['at'] as int;

      final scheduled = await reviewCard(
        state: state,
        answer: Answer.know,
        at: at,
      );

      expect(scheduled.due, step['due']);
      expect(scheduled.state.lastReview, at);
      expect(scheduled.state.stability, _closeTo(step['stability'] as double));
      expect(
        scheduled.state.difficulty,
        _closeTo(step['difficulty'] as double),
      );
      expect(
        await retrievability(state: state, at: at),
        _closeTo(step['retrievability'] as double),
      );
    },
  );

  test('reviewing with a fuzz factor returns the fuzzed reference step of the engine', () async {
    final fixtures =
        jsonDecode(File(_fixtures).readAsStringSync()) as Map<String, dynamic>;
    final reviews =
        ((fixtures['fuzzed_sequences'] as List<dynamic>).singleWhere((
              sequence,
            ) {
              final fields = sequence as Map<String, dynamic>;
              return fields['name'] == 'good-on-due' && fields['seed'] == 1;
            }) as Map<String, dynamic>)['reviews']
            as List<dynamic>;
    final previous = reviews[3] as Map<String, dynamic>;
    final step = reviews[4] as Map<String, dynamic>;
    expect(step['rating'], 3);
    final factor = step['fuzz_factor'] as double;

    final state = MemoryStateParts(
      stability: previous['stability'] as double,
      difficulty: previous['difficulty'] as double,
      lastReview: previous['at'] as int,
    );
    final at = step['at'] as int;

    final fuzzed = await reviewCard(
      state: state,
      answer: Answer.know,
      at: at,
      fuzzFactor: factor,
    );
    expect(fuzzed.due, step['due']);
    expect(fuzzed.state.stability, _closeTo(step['stability'] as double));
    // Control: without the factor, the same review falls due on another day.
    final plain = await reviewCard(state: state, answer: Answer.know, at: at);
    expect(plain.due, isNot(step['due']));
  });

  test(
    'a review dated before the last one arrives as a typed engine error',
    () async {
      const lastReview = 1767225600;
      final state = (await reviewNewCard(
        answer: Answer.know,
        at: lastReview,
      )).state;
      expect(state.lastReview, lastReview);

      await expectLater(
        reviewCard(state: state, answer: Answer.know, at: lastReview - 1),
        throwsA(
          const EngineError.reviewBeforeLastReview(
            lastReview: lastReview,
            review: lastReview - 1,
          ),
        ),
      );
      // Control: a review at the same instant has zero elapsed time and is accepted.
      expect(
        (await reviewCard(
          state: state,
          answer: Answer.know,
          at: lastReview,
        )).state.lastReview,
        lastReview,
      );
    },
  );
}
