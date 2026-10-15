import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import 'candidates.dart';
import 'capture_view.dart';
import 'extracting_view.dart';
import 'extraction_client.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'failure_view.dart';
import 'photo.dart';
import 'photo_source.dart';
import 'review_view.dart';

/// Every deck, kept current, for the target chip.
final _decksProvider = StreamProvider.autoDispose<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).watchDecks(),
);

/// Takes or picks one photo, extracts candidate cards from it, and saves the
/// ones the user keeps into [deck], or into a new deck when it is null.
/// Nothing is written before the user confirms; the screen then pops with the
/// [Deck] it saved into.
class PhotoImportScreen extends ConsumerStatefulWidget {
  const PhotoImportScreen({
    super.key,
    required this.deck,
    required this.client,
    required this.photos,
  });

  final DeckId? deck;
  final ExtractionClient client;
  final PhotoSource photos;

  @override
  ConsumerState<PhotoImportScreen> createState() => _PhotoImportScreenState();
}

sealed class _Stage {
  const _Stage();
}

final class _Capturing extends _Stage {
  const _Capturing();
}

final class _Extracting extends _Stage {
  _Extracting(this.photo);

  final JpegPhoto photo;
  final cancel = Completer<void>();
}

final class _Failed extends _Stage {
  const _Failed(this.failure, this.photo);

  final PhotoImportFailure failure;

  /// The photo a retry sends again; null when the failure came before one.
  final JpegPhoto? photo;
}

final class _Reviewing extends _Stage {
  const _Reviewing(this.review);

  final Review review;
}

class _PhotoImportScreenState extends ConsumerState<PhotoImportScreen> {
  _Stage _stage = const _Capturing();

  /// The deck the cards go into; null for a new deck.
  late DeckId? _target = widget.deck;

  bool _saving = false;

  @override
  void dispose() {
    if (_stage case _Extracting(:final cancel) when !cancel.isCompleted) {
      cancel.complete();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(_decksProvider);
    final target = switch (decks) {
      AsyncData(:final value) => value.where((deck) => deck.id == _target),
      _ => const <Deck>[],
    }.firstOrNull;
    final l10n = AppLocalizations.of(context);
    final targetName = target?.name ?? l10n.newDeck;
    return switch (_stage) {
      _Capturing() => CaptureView(
        photos: widget.photos,
        decks: decks.value ?? const [],
        target: target,
        onTarget: (deck) => setState(() => _target = deck),
        onPhoto: _extract,
        onFailure: (failure) => setState(() => _stage = _Failed(failure, null)),
      ),
      _Extracting(:final photo) => ExtractingView(
        photo: photo,
        onCancel: _cancel,
      ),
      _Failed(:final failure, :final photo) => FailureView(
        failure: failure,
        onRetry: photo == null || !isRetryable(failure)
            ? null
            : () => _extract(photo),
        onRetake: _retake,
      ),
      _Reviewing(:final review) => ReviewView(
        review: review,
        deckName: targetName,
        saving: _saving,
        onChanged: () => setState(() {}),
        onRetake: _retake,
        onSave: () => _save(review),
      ),
    };
  }

  Future<void> _extract(JpegPhoto photo) async {
    final stage = _Extracting(photo);
    setState(() => _stage = stage);
    final target = _target;
    final repository = ref.read(deckRepositoryProvider);
    bool current() => mounted && identical(_stage, stage);
    try {
      final cards = await widget.client.extract(
        photo,
        cancel: stage.cancel.future,
      );
      if (cards == null || !current()) return;
      final existing = target == null
          ? const <Card>[]
          : await repository.listCards(target);
      if (!current()) return;
      setState(
        () => _stage = _Reviewing(
          Review(cards, {for (final card in existing) card.cardKey}),
        ),
      );
    } on PhotoImportFailure catch (failure) {
      if (current()) setState(() => _stage = _Failed(failure, photo));
    } on DeckFailure catch (failure) {
      if (!current()) return;
      _showDeckFailure(failure);
      setState(() => _stage = const _Capturing());
    }
  }

  void _cancel() {
    if (_stage case _Extracting(:final cancel)) cancel.complete();
    setState(() => _stage = const _Capturing());
  }

  void _retake() => setState(() => _stage = const _Capturing());

  Future<void> _save(Review review) async {
    final l10n = AppLocalizations.of(context);
    final ImportTarget target;
    if (_target case final deck?) {
      target = ImportIntoDeck(deck);
    } else {
      final name = await showNameSheet(
        context,
        title: l10n.newDeck,
        action: l10n.create,
      );
      if (name == null || !mounted) return;
      target = ImportIntoNewDeck(name);
    }
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(deckRepositoryProvider)
          .importCards(target, review.toImport());
      navigator.pop(result.deck);
    } on DeckFailure catch (failure) {
      _showDeckFailure(failure);
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showDeckFailure(DeckFailure failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(describeFailure(AppLocalizations.of(context), failure)),
      ),
    );
  }
}
