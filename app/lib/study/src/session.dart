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

/// The deck's cards could not be read.
final class CardsUnreadable extends SessionLoadFailed {
  const CardsUnreadable(this.failure);

  final DeckFailure failure;
}

/// The cards' scheduling states could not be read.
final class StatesUnreadable extends SessionLoadFailed {
  const StatesUnreadable(this.failure);

  final StudyFailure failure;
}

/// [current] is on screen, below the card answered just before it.
final class SessionStudying extends SessionState {
  const SessionStudying(this.current, this.previous);

  final Card current;
  final PreviousCard? previous;
}

/// The session is over. [previous] is the last card answered while it can
/// still be corrected, which reopens the session.
final class SessionFinished extends SessionState {
  const SessionFinished(this.summary, this.previous);

  final SessionSummary summary;
  final PreviousCard? previous;
}

/// The card answered just before the one on screen.
final class PreviousCard {
  const PreviousCard(this.card, this.answer);

  final Card card;
  final Answer answer;

  /// Only a "Know" can be corrected, to "Don't know".
  bool get correctable => answer == Answer.know;
}

/// The counts a finished session shows.
final class SessionSummary {
  const SessionSummary({
    required this.cardsStudied,
    required this.knowCount,
    required this.dontKnowCount,
    required this.timeSpent,
  });

  /// Distinct cards answered at least once.
  final int cardsStudied;

  /// Answers given with each button; a re-shown card counts each time.
  final int knowCount;
  final int dontKnowCount;
  final Duration timeSpent;
}

/// An answer given in this session, and the card's state before it once its
/// write has read it.
final class _Answered {
  _Answered(this.review, this.card);

  final Review review;
  final Card card;
  ({CardState? state})? before;
}

/// One study session over a deck.
///
/// Every answer advances the session at once. The engine call and the write
/// that follow run afterwards, one at a time in answer order, and a
/// [StudyFailure] they raise goes to [onFailure].
class StudySession extends ChangeNotifier {
  StudySession({
    required DeckId deckId,
    required DeckRepository cards,
    required this._repository,
    required this._scheduler,
    required this._clock,
    required this._onFailure,
  }) {
    _load(deckId, cards);
  }

  final StudyRepository _repository;
  final Scheduler _scheduler;
  final DateTime Function() _clock;
  final void Function(StudyFailure failure) _onFailure;

  SessionLoadFailed? _loadFailure;
  bool _loaded = false;
  final _queue = <Card>[];
  final _states = <CardId, CardState>{};
  final _studied = <CardId>{};
  var _knowCount = 0;
  var _dontKnowCount = 0;
  late DateTime _startedAt;
  late DateTime _shownAt;
  DateTime? _endedAt;
  bool _left = false;
  bool _disposed = false;
  _Answered? _previous;
  Future<void> _writes = Future.value();

  SessionState get state {
    if (_loadFailure case final failure?) return failure;
    if (!_loaded) return const SessionLoading();
    final previous = switch (_previous) {
      final answered? => PreviousCard(answered.card, answered.review.answer),
      null => null,
    };
    if (_endedAt case final endedAt?) {
      return SessionFinished(
        SessionSummary(
          cardsStudied: _studied.length,
          knowCount: _knowCount,
          dontKnowCount: _dontKnowCount,
          timeSpent: endedAt.difference(_startedAt),
        ),
        _left ? null : previous,
      );
    }
    return SessionStudying(_queue.first, previous);
  }

  /// Completes when every answer given so far has been written or reported.
  Future<void> get settled => _writes;

  /// Answers the card on screen and shows the next.
  void answer(Answer answer) {
    if (state is! SessionStudying) return;
    final now = _clock();
    final card = _queue.removeAt(0);
    final answered = _Answered(
      Review(
        id: _repository.newReviewId(),
        cardId: card.id,
        answer: answer,
        reviewedAt: now,
        duration: now.difference(_shownAt),
      ),
      card,
    );
    _studied.add(card.id);
    switch (answer) {
      case Answer.know:
        _knowCount++;
      case Answer.dontKnow:
        _dontKnowCount++;
        reinsert(_queue, card);
    }
    _previous = answered;
    _shownAt = now;
    if (_queue.isEmpty) _endedAt = now;
    notifyListeners();
    _write(answered);
  }

  /// Changes the previous card's "Know" to "Don't know", rescheduling it from
  /// its state before that answer and showing it again later.
  void correctPrevious() {
    final previous = _previous;
    if (_left || previous == null || previous.review.answer != Answer.know) {
      return;
    }
    final original = previous.review;
    final corrected = Review(
      id: original.id,
      cardId: original.cardId,
      answer: Answer.dontKnow,
      reviewedAt: original.reviewedAt,
      duration: original.duration,
    );
    final answered = _Answered(corrected, previous.card);
    _knowCount--;
    _dontKnowCount++;
    if (_queue.isEmpty) {
      _endedAt = null;
      _shownAt = _clock();
    }
    reinsert(_queue, previous.card);
    _previous = answered;
    notifyListeners();
    _write(answered, corrects: previous);
  }

  /// Ends the session early; the summary shows and nothing can be corrected.
  void leave() {
    if (state is! SessionStudying) return;
    _endedAt = _clock();
    _left = true;
    notifyListeners();
  }

  Future<void> _load(DeckId deckId, DeckRepository cards) async {
    try {
      final deckCards = await cards.listCards(deckId);
      final states = await _repository.statesOf([
        for (final card in deckCards) card.id,
      ]);
      final now = _clock();
      _states.addAll(states);
      _queue.addAll(buildQueue(deckCards, states, now));
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

  /// Queues the engine call and write for [answered], behind every earlier
  /// one. A correction passes the answer it [corrects], whose pre-answer state
  /// that earlier write has read by the time this one runs.
  void _write(_Answered answered, {_Answered? corrects}) {
    _writes = _writes.then((_) async {
      final review = answered.review;
      final before = corrects?.before ?? (state: _states[review.cardId]);
      answered.before = before;
      try {
        final after = await _scheduler.review(
          before.state,
          review.answer,
          review.reviewedAt,
        );
        await _repository.record(review, after);
        _states[review.cardId] = after;
      } on StudyFailure catch (failure) {
        _onFailure(failure);
      }
    });
  }
}
