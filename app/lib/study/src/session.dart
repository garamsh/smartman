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
/// Practice shows the same way.
final class SessionStudying extends SessionState {
  const SessionStudying(this.current, this.previous, this.progress);

  final Card current;

  /// Oldest first.
  final List<PreviousCard> previous;
  final SessionProgress progress;
}

/// No card is left today: the completion card takes the current card's
/// place, below every card answered so far in [previous].
final class SessionComplete extends SessionState {
  const SessionComplete(this.completion, this.previous, this.progress);

  final Completion completion;

  /// Oldest first.
  final List<PreviousCard> previous;
  final SessionProgress progress;
}

/// No card is left today and none of the decks' cards was answered today.
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

/// How many of the session's cards have been answered at least once.
final class SessionProgress {
  const SessionProgress(this.answered, this.total);

  final int answered;

  /// The cards in the queue when the session opened.
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

/// An answer given in this session. A written answer holds the [review]
/// that records it; a practice answer holds the [pass] it was given in and is
/// never written.
final class _Answered {
  _Answered.written(this.card, Review this.review)
    : answer = review.answer,
      first = review.answer,
      pass = null;

  _Answered.practice(this.card, this.answer, {required int this.pass})
    : review = null,
      first = answer;

  final Card card;
  Answer answer;
  Review? review;
  final Answer first;
  final int? pass;

  void toggle() {
    answer = switch (answer) {
      Answer.know => Answer.dontKnow,
      Answer.dontKnow => Answer.know,
    };
    review = review?.withAnswer(answer);
  }
}

/// Which cards a practice pass shows.
enum _Pass {
  /// Every card of the practice set, shuffled.
  all,

  /// The cards missed in the pass over all, until each is answered right.
  missed,
}

/// One study session over one or more decks.
///
/// It shows the cards left today, then the completion card; from there,
/// [practice] goes on over the cards answered today, which writes nothing.
///
/// Every random choice, the queue's order, each re-show gap, each answer's
/// fuzz factor and the practice order, is drawn from the one [Random] the
/// session receives.
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
  var _total = 0;

  /// Each card's stored state when the session opened; a new card is absent.
  final _before = <CardId, CardState>{};
  final _answers = <_Answered>[];
  late DateTime _shownAt;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  /// The answers stored today for the decks' cards before the session
  /// opened, oldest first.
  var _storedToday = const <StoredAnswer>[];

  /// The cards those answers are to, each once, in the order first answered.
  var _answeredToday = const <Card>[];

  /// The time of every stored answer when the session opened, for the
  /// streak.
  var _storedTimes = const <DateTime>[];

  bool _practicing = false;
  var _pass = _Pass.all;

  /// Counts the practice passes started, so a toggle can tell whether its
  /// answer belongs to the pass under way.
  var _passNumber = 0;
  final _practiceQueue = <Card>[];

  /// The cards answered "Don't know" in the pass over all, oldest first.
  final _missed = <Card>[];

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
        for (final answered in _answers)
          if (answered.review != null) answered.card.id,
      }.length,
      _total,
    );
    if (_practicing) {
      return SessionStudying(_practiceQueue.first, previous, progress);
    }
    if (_queue.isNotEmpty) {
      return SessionStudying(_queue.first, previous, progress);
    }
    if (_practiceSet.isEmpty) return const SessionEmpty();
    return SessionComplete(_completion(), previous, progress);
  }

  /// The answers given in this session that are written, as they stand.
  Iterable<_Answered> get _written =>
      _answers.where((answered) => answered.review != null);

  /// Every card answered today: before the session opened, then in it.
  List<Card> get _practiceSet {
    final seen = <CardId>{};
    return [
      for (final card in [
        ..._answeredToday,
        for (final answered in _written) answered.card,
      ])
        if (seen.add(card.id)) card,
    ];
  }

  Completion _completion() {
    final written = _written.toList();
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
        for (final answered in written) answered.review!.duration,
      ].fold(Duration.zero, (sum, duration) => sum + duration),
      streak: streak(
        [
          for (final answered in written) answered.review!.reviewedAt,
          ..._storedTimes,
        ],
        _clock(),
        _offsetAt,
      ),
    );
  }

  /// Completes when every answer and toggle given so far has been written or
  /// reported.
  Future<void> get settled => _writes;

  /// Answers the card on screen and shows the next. A practice answer is
  /// kept in the session alone.
  void answer(Answer answer) {
    if (state is! SessionStudying) return;
    if (_practicing) return _answerPractice(answer);
    final now = _clock();
    final card = _queue.removeAt(0);
    _answers.add(
      _Answered.written(
        card,
        Review(
          id: _repository.newReviewId(),
          cardId: card.id,
          answer: answer,
          reviewedAt: now,
          duration: now.difference(_shownAt),
          fuzzFactor: FuzzFactor.draw(_random),
        ),
      ),
    );
    if (answer == Answer.dontKnow) reinsert(_queue, card, _random);
    _shownAt = now;
    notifyListeners();
    _write(card.id);
  }

  /// Goes on from the completion card as practice: every card answered
  /// today, shuffled; then the ones missed in that pass, each put back after
  /// a gap until answered right; then all again, until the user stops.
  void practice() {
    if (state is! SessionComplete) return;
    _practicing = true;
    _startPass(_Pass.all);
    notifyListeners();
  }

  void _startPass(_Pass pass) {
    final cards = switch (pass) {
      _Pass.all => _practiceSet,
      _Pass.missed => List.of(_missed),
    };
    _pass = pass;
    _passNumber++;
    _missed.clear();
    _practiceQueue.addAll(orderQueue(SelectedQueue.current(cards), _random));
  }

  void _answerPractice(Answer answer) {
    final card = _practiceQueue.removeAt(0);
    _answers.add(_Answered.practice(card, answer, pass: _passNumber));
    if (answer == Answer.dontKnow) {
      switch (_pass) {
        case _Pass.all:
          _missed.add(card);
        case _Pass.missed:
          reinsert(_practiceQueue, card, _random);
      }
    }
    if (_practiceQueue.isEmpty) {
      _startPass(
        _pass == _Pass.all && _missed.isNotEmpty ? _Pass.missed : _Pass.all,
      );
    }
    notifyListeners();
  }

  /// Toggles the answer at [position] between "Know" and "Don't know".
  ///
  /// A written answer is rescheduled by replaying its card's written answers
  /// in this session, each with the fuzz factor drawn when it was given.
  /// Before practice, a toggle to "Don't know" of a card's last answer puts
  /// the card back as an answer would, unless it is already waiting, which
  /// takes the completion card away again; a toggle to "Know" of a card's last
  /// answer removes the card's re-show if it is waiting behind the card on
  /// screen.
  ///
  /// A practice answer is not written. A toggle of the last answer of its
  /// card in the pass under way has the same effects on the practice queue: in
  /// the pass over all it adds the card to or removes it from the missed.
  void toggle(int position) {
    if (!_loaded) return;
    final answered = _answers[position]..toggle();
    final card = answered.card;
    final isLast = !_answers
        .skip(position + 1)
        .any(
          (later) => later.card.id == card.id && later.pass == answered.pass,
        );
    if (answered.pass case final pass?) {
      if (isLast && pass == _passNumber) _togglePractice(card, answered.answer);
      notifyListeners();
      return;
    }
    if (!_practicing) _toggleQueued(_queue, card, answered.answer, isLast);
    notifyListeners();
    _write(card.id);
  }

  void _togglePractice(Card card, Answer answer) {
    switch (_pass) {
      case _Pass.all:
        _missed.removeWhere((missed) => missed.id == card.id);
        if (answer == Answer.dontKnow) _missed.add(card);
      case _Pass.missed:
        _toggleQueued(_practiceQueue, card, answer, true);
    }
  }

  /// Puts [card] back into [queue] for a toggle to "Don't know", or takes its
  /// re-show out for one to "Know", when the toggled answer [isLast].
  void _toggleQueued(List<Card> queue, Card card, Answer answer, bool isLast) {
    if (!isLast) return;
    final waiting = queue.indexWhere((queued) => queued.id == card.id);
    if (answer == Answer.dontKnow && waiting == -1) {
      if (queue.isEmpty) _shownAt = _clock();
      reinsert(queue, card, _random);
    } else if (answer == Answer.know && waiting > 0) {
      queue.removeAt(waiting);
    }
  }

  Future<void> _load(DeckSelection decks, DeckRepository cards) async {
    try {
      final (read, states) = await readCards(decks, cards, _repository);
      final now = _clock();
      final start = studyDayStart(now, _offsetAt);
      final day = StudyDay.at(
        now,
        firstAnswers: await _repository.firstAnswersSince(start),
        offsetAt: _offsetAt,
      );
      final byId = {for (final card in read) card.id: card};
      _storedToday = [
        for (final stored in await _repository.answersSince(start))
          if (byId.containsKey(stored.card)) stored,
      ];
      _answeredToday = [
        for (final id in {for (final stored in _storedToday) stored.card})
          byId[id]!,
      ];
      _storedTimes = await _repository.answerTimes();
      _before.addAll(states);
      _queue.addAll(orderQueue(selectQueue(read, states, day), _random));
      _total = _queue.length;
      _shownAt = now;
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
      for (final answered in _written)
        if (answered.card.id == card) answered.review!,
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
