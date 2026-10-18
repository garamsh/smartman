import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../deck/deck.dart';
import 'failure.dart';
import 'model.dart';
import 'queue.dart';
import 'rust/api/engine.dart';
import 'scheduler.dart';
import 'study_repository.dart';
import 'study_time.dart';

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
  const SessionStudying(
    this.current,
    this.previous,
    this.progress, {
    this.guide,
  });

  final Card current;

  /// Oldest first.
  final List<PreviousCard> previous;
  final SessionProgress progress;

  /// Before the session's first answer, the session's size the guide in the
  /// previous card's place shows; otherwise null, and no guide shows.
  final SessionSize? guide;
}

/// How many cards a session opened with, and the whole minutes they take at
/// the user's pace, as the today card counts them.
final class SessionSize {
  const SessionSize({required this.cards, required this.minutes});

  final int cards;
  final int minutes;

  @override
  bool operator ==(Object other) =>
      other is SessionSize && other.cards == cards && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(cards, minutes);
}

/// No card is left today: the completion card takes the current card's
/// place, below every card answered so far in [previous].
final class SessionComplete extends SessionState {
  const SessionComplete(
    this.completion,
    this.previous,
    this.progress, {
    required this.more,
  });

  final Completion completion;

  /// Whether new cards are left past today's, which [StudySession.studyOn]
  /// goes on with; otherwise no card is left to take.
  final bool more;

  /// Oldest first.
  final List<PreviousCard> previous;
  final SessionProgress progress;
}

/// No card is left to take and none of the decks' cards was answered today.
final class SessionEmpty extends SessionState {
  const SessionEmpty();
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

/// How many of the day's cards have been answered at least once today, in
/// this session or an earlier one.
final class SessionProgress {
  const SessionProgress(this.answered, this.total);

  final int answered;

  /// The day's cards: those of the decks answered today before the session
  /// opened, the queue it opened with, and those taken past today's since.
  final int total;
}

/// What the completion card shows of today's study day over the session's
/// decks: the stored answers given before the session opened and the
/// session's own, as they stand.
final class Completion {
  const Completion({
    required this.knowCount,
    required this.dontKnowCount,
    required this.timeSpent,
    required this.streak,
  });

  /// Answers standing as each choice; a re-shown card counts each time.
  final int knowCount;
  final int dontKnowCount;

  /// The time the cards were on screen before their answers.
  final Duration timeSpent;

  /// Study days in a row with an answer, across every deck ([streak]).
  final int streak;
}

/// An answer given in this session and the [review] that records it.
final class _Answered {
  _Answered(this.card, this.review) : first = review.answer;

  final Card card;
  Review review;
  final Answer first;

  Answer get answer => review.answer;

  void toggle() => review = review.withAnswer(switch (answer) {
    Answer.know => Answer.dontKnow,
    Answer.dontKnow => Answer.know,
  });
}

/// One study session over one or more decks.
///
/// It shows the cards left today, then the completion card; from there,
/// [studyOn] goes on with the new cards past today's, oldest first, each
/// answer recorded as any other. A session that opens with no card left today
/// starts on those at once.
///
/// Every random choice, the queue's order, each re-show gap and each answer's
/// fuzz factor, is drawn from the one [Random] the session receives.
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
    this._offsetAt = localOffsetAt,
  }) {
    _load(decks, cards);
  }

  final StudyRepository _repository;
  final Random _random;
  final Scheduler _scheduler;
  final DateTime Function() _clock;
  final void Function(StudyFailure failure) _onFailure;
  final UtcOffsetAt _offsetAt;

  SessionLoadFailed? _loadFailure;
  bool _loaded = false;
  final _queue = <Card>[];

  /// The day's cards, each once: those answered today before the session
  /// opened, the queue it opened with, and those taken past today's since.
  final _dayCards = <CardId>{};

  /// The new cards past today's, oldest first, not yet taken.
  var _more = const <Card>[];

  /// Each card's stored state when the session opened; a new card is absent.
  final _before = <CardId, CardState>{};
  final _answers = <_Answered>[];
  late DateTime _shownAt;

  /// When the app last left the foreground while the card on screen waited,
  /// or null while it is in the foreground.
  DateTime? _pausedAt;

  /// The time out of the foreground since the card on screen was shown,
  /// up to [_pausedAt].
  var _away = Duration.zero;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  /// The answers stored today for the decks' cards before the session
  /// opened, oldest first.
  var _storedToday = const <StoredAnswer>[];

  /// The cards those answers are to, each once, in the order first answered.
  var _answeredToday = const <Card>[];

  /// When the study day the session opened in started.
  late DateTime _openedDay;

  /// The time of every stored answer given since [_openedDay], in any deck,
  /// for the streak.
  var _storedTimes = const <DateTime>[];

  /// How many study days in a row before [_openedDay] hold a stored answer.
  var _daysBefore = 0;

  /// The session's size when it opened.
  var _size = const SessionSize(cards: 0, minutes: 0);

  SessionState get state {
    if (_loadFailure case final failure?) return failure;
    if (!_loaded) return const SessionLoading();
    final previous = [
      for (final (position, answered) in _answers.indexed)
        PreviousCard(
          position: position,
          card: answered.card,
          answer: answered.answer,
          changed: answered.answer != answered.first,
        ),
    ];
    final progress = SessionProgress(
      {
        for (final card in _answeredToday) card.id,
        for (final answered in _answers) answered.card.id,
      }.length,
      _dayCards.length,
    );
    if (_queue.isNotEmpty) {
      return SessionStudying(
        _queue.first,
        previous,
        progress,
        guide: _answers.isEmpty ? _size : null,
      );
    }
    if (_answeredToday.isEmpty && _answers.isEmpty) return const SessionEmpty();
    return SessionComplete(
      _completion(),
      previous,
      progress,
      more: _more.isNotEmpty,
    );
  }

  Completion _completion() {
    final written = _answers;
    final answers = [
      for (final stored in _storedToday) stored.answer,
      for (final answered in written) answered.answer,
    ];
    return Completion(
      knowCount: answers.where((answer) => answer == Answer.know).length,
      dontKnowCount: answers
          .where((answer) => answer == Answer.dontKnow)
          .length,
      timeSpent: [
        for (final stored in _storedToday) stored.duration,
        for (final answered in written) answered.review.duration,
      ].fold(Duration.zero, (sum, duration) => sum + duration),
      streak: streak(
        [
          for (final answered in written) answered.review.reviewedAt,
          ..._storedTimes,
        ],
        _clock(),
        since: _openedDay,
        daysBefore: _daysBefore,
        offsetAt: _offsetAt,
      ),
    );
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
          duration: _onScreen(now),
          fuzzFactor: FuzzFactor.draw(_random),
        ),
      ),
    );
    if (answer == Answer.dontKnow) reinsert(_queue, card, _random);
    _show(now);
    notifyListeners();
    _write(card.id);
  }

  /// Stops the clock of the card on screen while the app is out of the
  /// foreground, so an answer's duration counts only the time it was in it.
  void pause() => _pausedAt ??= _clock();

  /// Starts the clock of the card on screen again as the app comes back to
  /// the foreground.
  void resume() {
    if (_pausedAt case final since?) _away += _clock().difference(since);
    _pausedAt = null;
  }

  /// Starts the clock of the next card shown, at [now].
  void _show(DateTime now) {
    _shownAt = now;
    _away = Duration.zero;
    if (_pausedAt != null) _pausedAt = now;
  }

  /// The time the card on screen has been shown at [now] with the app in the
  /// foreground.
  Duration _onScreen(DateTime now) {
    final away = switch (_pausedAt) {
      final since? => _away + now.difference(since),
      null => _away,
    };
    final shown = now.difference(_shownAt) - away;
    return shown.isNegative ? Duration.zero : shown;
  }

  /// Goes on from the completion card with the new cards past today's,
  /// oldest first; with none left, does nothing.
  void studyOn() {
    if (state is! SessionComplete || _more.isEmpty) return;
    _takeMore();
    _show(_clock());
    notifyListeners();
  }

  /// Moves the new cards past today's into the queue.
  void _takeMore() {
    _queue.addAll(_more);
    _dayCards.addAll([for (final card in _more) card.id]);
    _more = const [];
  }

  /// Toggles the answer at [position] between "Know" and "Don't know".
  ///
  /// The answer is rescheduled by replaying its card's answers in this
  /// session, each with the fuzz factor drawn when it was given. A toggle to
  /// "Don't know" of a card's last answer puts the card back as an answer
  /// would, unless it is already waiting, which takes the completion card away
  /// again; a toggle to "Know" of a card's last answer removes the card's
  /// re-show if it is waiting behind the card on screen.
  void toggle(int position) {
    if (!_loaded) return;
    final answered = _answers[position]..toggle();
    final card = answered.card;
    final isLast = !_answers
        .skip(position + 1)
        .any((later) => later.card.id == card.id);
    _toggleQueued(card, answered.answer, isLast);
    notifyListeners();
    _write(card.id);
  }

  /// Changes the answer at [position] to [answer], as [toggle] does; an
  /// answer that already stands as [answer] is left as it is.
  void redecide(int position, Answer answer) {
    if (!_loaded || _answers[position].answer == answer) return;
    toggle(position);
  }

  /// Puts [card] back into the queue for a toggle to "Don't know", or takes
  /// its re-show out for one to "Know", when the toggled answer [isLast].
  void _toggleQueued(Card card, Answer answer, bool isLast) {
    if (!isLast) return;
    final waiting = _queue.indexWhere((queued) => queued.id == card.id);
    if (answer == Answer.dontKnow && waiting == -1) {
      if (_queue.isEmpty) _show(_clock());
      reinsert(_queue, card, _random);
    } else if (answer == Answer.know && waiting > 0) {
      _queue.removeAt(waiting);
    }
  }

  Future<void> _load(DeckSelection decks, DeckRepository cards) async {
    try {
      final (read, states) = await readCards(decks, cards, _repository);
      final now = _clock();
      final start = studyDayStart(now, _offsetAt);
      final (day, pace) = await readStudyDay(_repository, now, _offsetAt);
      final byId = {for (final card in read) card.id: card};
      final storedSince = await _repository.answersSince(start);
      _storedToday = [
        for (final stored in storedSince)
          if (byId.containsKey(stored.card)) stored,
      ];
      _answeredToday = [
        for (final id in {for (final stored in _storedToday) stored.card})
          byId[id]!,
      ];
      _openedDay = start;
      _storedTimes = [for (final stored in storedSince) stored.at];
      _daysBefore = await studyDaysBefore(
        start,
        _repository.latestAnswerBefore,
        _offsetAt,
      );
      _before.addAll(states);
      _queue.addAll(orderQueue(selectQueue(read, states, day), _random));
      _dayCards.addAll([
        for (final card in _answeredToday) card.id,
        for (final card in _queue) card.id,
      ]);
      final taken = {for (final card in _queue) card.id};
      _more = [
        for (final card in newCards(read, states))
          if (!taken.contains(card.id)) card,
      ];
      final fresh = _queue.where((card) => !states.containsKey(card.id)).length;
      _size = SessionSize(
        cards: _queue.length,
        minutes: pace.minutes(reviews: _queue.length - fresh, fresh: fresh),
      );
      // Opening the screen with no card left today is the choice to go on.
      if (_queue.isEmpty) _takeMore();
      _show(now);
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
  /// written answers in this session, as they stand now, replayed from its
  /// state when the session opened, then written with that state.
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
          fuzz: history.first.fuzzFactor,
        );
        for (final review in history.skip(1)) {
          after = await _scheduler.review(
            after,
            review.answer,
            review.reviewedAt,
            fuzz: review.fuzzFactor,
          );
        }
        await _repository.record(card, history, after, at: _clock());
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
