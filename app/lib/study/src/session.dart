import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../deck/deck.dart';
import 'failure.dart';
import 'model.dart';
import 'queue.dart';
import 'rust/api/engine.dart';
import 'scheduler.dart';
import 'study_repository.dart';

/// What a session shows.
sealed class SessionState {
  const SessionState();
}

/// The queue is being read.
final class SessionLoading extends SessionState {
  const SessionLoading();
}

/// The queue could not be read.
sealed class SessionLoadFailed extends SessionState {
  const SessionLoadFailed();
}

/// The decks' cards could not be read.
final class CardsUnreadable extends SessionLoadFailed {
  const CardsUnreadable(this.failure);

  final DeckFailure failure;
}

/// The cards' scheduling states could not be read.
final class StatesUnreadable extends SessionLoadFailed {
  const StatesUnreadable(this.failure);

  final StudyFailure failure;
}

/// [current] is on screen, below every card answered so far in [previous].
final class SessionStudying extends SessionState {
  const SessionStudying(this.current, this.previous, this.progress);

  final Card current;

  /// Oldest first.
  final List<PreviousCard> previous;
  final SessionProgress progress;
}

/// The session is over. [previous] holds the answers that can still be
/// toggled, oldest first; it is empty once the user has left.
final class SessionFinished extends SessionState {
  const SessionFinished(this.summary, this.previous, this.progress);

  final SessionSummary summary;
  final List<PreviousCard> previous;
  final SessionProgress progress;
}

/// An answer given in this session, shown above the current card.
final class PreviousCard {
  const PreviousCard({
    required this.position,
    required this.card,
    required this.answer,
    required this.changed,
  });

  /// Where the answer stands among the session's answers, first at 0; what
  /// [StudySession.toggle] takes.
  final int position;
  final Card card;
  final Answer answer;

  /// Whether [answer] differs from the answer first given.
  final bool changed;
}

/// How many of the session's cards have been answered at least once.
final class SessionProgress {
  const SessionProgress(this.answered, this.total);

  final int answered;

  /// The cards in the queue when the session opened.
  final int total;
}

/// The counts a finished session shows, from the current answers.
final class SessionSummary {
  const SessionSummary({
    required this.cardsStudied,
    required this.knowCount,
    required this.dontKnowCount,
    required this.timeSpent,
  });

  /// Distinct cards answered at least once.
  final int cardsStudied;

  /// Answers standing as each choice; a re-shown card counts each time.
  final int knowCount;
  final int dontKnowCount;
  final Duration timeSpent;
}

/// An answer given in this session; [review] holds its current answer.
final class _Answered {
  _Answered(this.card, this.review) : first = review.answer;

  final Card card;
  Review review;
  final Answer first;
}

/// One study session over one or more decks.
///
/// Every random choice, the queue's order and each re-show gap, is drawn from
/// the one [Random] the session receives.
///
/// Every answer and every toggle changes the session at once. The engine calls
/// and the write that follow run afterwards, one at a time in the order given,
/// and a [StudyFailure] they raise goes to [onFailure]. Any other error is
/// reported to [FlutterError.reportError], and the writes after it still run.
class StudySession extends ChangeNotifier {
  StudySession({
    required DeckSelection decks,
    required DeckRepository cards,
    required this._repository,
    required this._scheduler,
    required this._clock,
    required this._random,
    required this._onFailure,
  }) {
    _load(decks, cards);
  }

  final StudyRepository _repository;
  final Random _random;
  final Scheduler _scheduler;
  final DateTime Function() _clock;
  final void Function(StudyFailure failure) _onFailure;

  SessionLoadFailed? _loadFailure;
  bool _loaded = false;
  final _queue = <Card>[];
  var _total = 0;

  /// Each card's stored state when the session opened; a new card is absent.
  final _before = <CardId, CardState>{};
  final _answers = <_Answered>[];
  late DateTime _startedAt;
  late DateTime _shownAt;
  DateTime? _endedAt;
  bool _left = false;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  SessionState get state {
    if (_loadFailure case final failure?) return failure;
    if (!_loaded) return const SessionLoading();
    final previous = [
      for (final (position, answered) in _answers.indexed)
        PreviousCard(
          position: position,
          card: answered.card,
          answer: answered.review.answer,
          changed: answered.review.answer != answered.first,
        ),
    ];
    final progress = SessionProgress(
      {for (final answered in _answers) answered.card.id}.length,
      _total,
    );
    if (_endedAt case final endedAt?) {
      return SessionFinished(
        SessionSummary(
          cardsStudied: progress.answered,
          knowCount: previous.where((p) => p.answer == Answer.know).length,
          dontKnowCount: previous
              .where((p) => p.answer == Answer.dontKnow)
              .length,
          timeSpent: endedAt.difference(_startedAt),
        ),
        _left ? const [] : previous,
        progress,
      );
    }
    return SessionStudying(_queue.first, previous, progress);
  }

  /// Completes when every answer and toggle given so far has been written or
  /// reported.
  Future<void> get settled => _writes;

  /// Answers the card on screen and shows the next.
  void answer(Answer answer) {
    if (state is! SessionStudying) return;
    final now = _clock();
    final card = _queue.removeAt(0);
    _answers.add(
      _Answered(
        card,
        Review(
          id: _repository.newReviewId(),
          cardId: card.id,
          answer: answer,
          reviewedAt: now,
          duration: now.difference(_shownAt),
        ),
      ),
    );
    if (answer == Answer.dontKnow) reinsert(_queue, card, _random);
    _shownAt = now;
    if (_queue.isEmpty) _endedAt = now;
    notifyListeners();
    _write(card.id);
  }

  /// Toggles the answer at [position] between "Know" and "Don't know", and
  /// reschedules its card by replaying the card's answers in this session.
  ///
  /// A toggle to "Don't know" of a card's last answer puts the card back as
  /// an answer would, unless it is already waiting; after the queue has
  /// emptied this reopens the session. A toggle to "Know" of a card's last
  /// answer removes the card's re-show if it is waiting behind the card on
  /// screen.
  void toggle(int position) {
    if (_left || !_loaded) return;
    final answered = _answers[position];
    final card = answered.card;
    final answer = switch (answered.review.answer) {
      Answer.know => Answer.dontKnow,
      Answer.dontKnow => Answer.know,
    };
    answered.review = answered.review.withAnswer(answer);
    final isLast = !_answers
        .skip(position + 1)
        .any((later) => later.card.id == card.id);
    final waiting = _queue.indexWhere((queued) => queued.id == card.id);
    if (isLast && answer == Answer.dontKnow && waiting == -1) {
      if (_queue.isEmpty) {
        _endedAt = null;
        _shownAt = _clock();
      }
      reinsert(_queue, card, _random);
    } else if (isLast && answer == Answer.know && waiting > 0) {
      _queue.removeAt(waiting);
    }
    notifyListeners();
    _write(card.id);
  }

  /// Ends the session early; the summary shows and nothing can be toggled.
  void leave() {
    if (state is! SessionStudying) return;
    _endedAt = _clock();
    _left = true;
    notifyListeners();
  }

  Future<void> _load(DeckSelection decks, DeckRepository cards) async {
    try {
      final (read, states) = await readCards(decks, cards, _repository);
      final now = _clock();
      _before.addAll(states);
      _queue.addAll(orderQueue(selectQueue(read, states, now), _random));
      _total = _queue.length;
      _startedAt = now;
      _shownAt = now;
      if (_queue.isEmpty) _endedAt = now;
      _loaded = true;
    } on DeckFailure catch (failure) {
      _loadFailure = CardsUnreadable(failure);
    } on StudyFailure catch (failure) {
      _loadFailure = StatesUnreadable(failure);
    }
    // The screen may have closed while the queue was read.
    if (!_disposed) notifyListeners();
  }

  /// Stops notifying listeners. Writes already queued still run.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Queues the rescheduling of [card], behind every earlier write: its
  /// answers in this session, as they stand now, replayed from its state when
  /// the session opened, then written with that state.
  void _write(CardId card) {
    final history = [
      for (final answered in _answers)
        if (answered.card.id == card) answered.review,
    ];
    final before = _before[card];
    _writes = _writes.then((_) async {
      try {
        var after = await _scheduler.review(
          before,
          history.first.answer,
          history.first.reviewedAt,
        );
        for (final review in history.skip(1)) {
          after = await _scheduler.review(
            after,
            review.answer,
            review.reviewedAt,
          );
        }
        await _repository.record(card, history, after);
      } on StudyFailure catch (failure) {
        _onFailure(failure);
      } catch (error, stackTrace) {
        // Reported as uncaught rather than rethrown: an errored future would
        // skip every write queued behind it.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'study',
            context: ErrorDescription('while recording an answer'),
          ),
        );
      }
    });
  }
}
