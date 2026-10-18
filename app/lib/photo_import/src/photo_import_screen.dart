import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../deck/deck.dart';
import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../l10n/app_localizations.dart';
import 'candidates.dart';
import 'extracting_view.dart';
import 'extraction_client.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'failure_view.dart';
import 'photo.dart';
import 'photo_source.dart';
import 'review_view.dart';

/// The keys the storage given to photo import must be opened to cache.
const photoImportStorageKeys = {_coachShownKey};

/// Set once the review's coach has shown on this device.
const _coachShownKey = 'photoReviewCoachShown';

/// Every deck, kept current, for the target chip.
final _decksProvider = StreamProvider.autoDispose<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).watchDecks(),
);

/// Offers the camera and the library over [context], and with the photo
/// taken or picked opens the screen that extracts candidate cards from it and
/// saves the ones the user keeps into [deck], or into a new deck when it is
/// null. [preferences], opened to cache [photoImportStorageKeys], keeps
/// whether the review's coach has shown on this device. A cancel opens
/// nothing. Nothing is written before the user confirms; resolves to the
/// [Deck] saved into, or to null.
Future<Deck?> importFromPhoto(
  BuildContext context, {
  required DeckId? deck,
  required ExtractionClient client,
  required PhotoSource photos,
  required SharedPreferencesWithCache preferences,
}) async {
  final navigator = Navigator.of(context);
  final first = await _choosePhoto(context, photos);
  if (first == null) return null;
  return navigator.push(
    MaterialPageRoute<Deck>(
      builder: (_) => _PhotoImportScreen(
        first: first,
        deck: deck,
        client: client,
        photos: photos,
        preferences: preferences,
      ),
    ),
  );
}

/// Offers "사진 찍기" and "앨범에서 고르기" in a sheet over [context], then
/// the one chosen. Resolves to extracting its photo, or to the failure that
/// came instead; null when the sheet or the picker is cancelled.
Future<_Stage?> _choosePhoto(BuildContext context, PhotoSource photos) async {
  final l10n = AppLocalizations.of(context);
  final source = await showAppSheet<Future<JpegPhoto?> Function()>(
    context,
    builder: (context) => AppSheet(
      title: l10n.photoSourceTitle,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppListRow(
            title: l10n.photoCamera,
            leading: const Icon(LucideIcons.camera),
            onSheet: true,
            onTap: () => Navigator.of(context).pop(photos.takePhoto),
          ),
          AppListRow(
            title: l10n.photoAlbum,
            leading: const Icon(LucideIcons.images),
            onSheet: true,
            onTap: () => Navigator.of(context).pop(photos.pickFromLibrary),
          ),
        ],
      ),
    ),
  );
  try {
    final photo = await source?.call();
    return photo == null ? null : _Extracting(photo);
  } on PhotoImportFailure catch (failure) {
    return _Failed(failure, null);
  }
}

class _PhotoImportScreen extends ConsumerStatefulWidget {
  const _PhotoImportScreen({
    required this.first,
    required this.deck,
    required this.client,
    required this.photos,
    required this.preferences,
  });

  /// The photo to extract from, or the failure that came instead of one.
  final _Stage first;

  final DeckId? deck;
  final ExtractionClient client;
  final PhotoSource photos;
  final SharedPreferencesWithCache preferences;

  @override
  ConsumerState<_PhotoImportScreen> createState() => _PhotoImportScreenState();
}

sealed class _Stage {
  const _Stage();
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
  const _Reviewing(this.review, {required this.coach});

  /// Whether Review opens with its coach.
  final bool coach;

  final Review review;
}

class _PhotoImportScreenState extends ConsumerState<_PhotoImportScreen> {
  late _Stage _stage = widget.first;

  /// The deck the cards go into; null for a new deck.
  late DeckId? _target = widget.deck;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_stage case final _Extracting stage) _extract(stage);
  }

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
    return switch (_stage) {
      _Extracting(:final photo) => ExtractingView(
        photo: photo,
        onCancel: _cancel,
      ),
      _Failed(:final failure, :final photo) => FailureView(
        failure: failure,
        onRetry: photo == null || !isRetryable(failure)
            ? null
            : () => _start(_Extracting(photo)),
        onRetake: _retake,
        onOpenSettings: failure is PhotoAccessDenied ? _openSettings : null,
      ),
      _Reviewing(:final review, :final coach) => ReviewView(
        review: review,
        decks: decks.value ?? const [],
        target: target,
        onTarget: (deck) => _chooseTarget(review, deck),
        saving: _saving,
        coach: coach,
        onChanged: () => setState(() {}),
        onRetake: _retake,
        onSave: () => _save(review),
      ),
    };
  }

  /// Shows [stage], and extracts when it is extracting.
  void _start(_Stage stage) {
    setState(() => _stage = stage);
    if (stage case final _Extracting stage) _extract(stage);
  }

  Future<void> _extract(_Extracting stage) async {
    final target = _target;
    final repository = ref.read(deckRepositoryProvider);
    final navigator = Navigator.of(context);
    bool current() => mounted && identical(_stage, stage);
    try {
      final cards = await widget.client.extract(
        stage.photo,
        cancel: stage.cancel.future,
      );
      if (cards == null || !current()) return;
      final existing = await _keysOf(repository, target);
      if (!mounted || !identical(_stage, stage)) return;
      // The coach shows once per device, so it is stored as shown when it
      // first shows; under reduce motion it does not show.
      final coach =
          widget.preferences.getBool(_coachShownKey) != true &&
          !MediaQuery.disableAnimationsOf(context);
      if (coach) unawaited(widget.preferences.setBool(_coachShownKey, true));
      setState(
        () => _stage = _Reviewing(Review(cards, existing), coach: coach),
      );
    } on PhotoImportFailure catch (failure) {
      if (current()) setState(() => _stage = _Failed(failure, stage.photo));
    } on DeckFailure catch (failure) {
      if (!current()) return;
      _showDeckFailure(failure);
      navigator.pop();
    }
  }

  /// The card keys [deck] holds; none for a new deck.
  static Future<Set<CardKey>> _keysOf(
    DeckRepository repository,
    DeckId? deck,
  ) async => deck == null
      ? const {}
      : {for (final card in await repository.listCards(deck)) card.cardKey};

  /// Saves into [deck] from now on, with the rows grouped against its keys
  /// once they are read.
  Future<void> _chooseTarget(Review review, DeckId? deck) async {
    setState(() => _target = deck);
    try {
      final existing = await _keysOf(ref.read(deckRepositoryProvider), deck);
      if (mounted && _target == deck) {
        setState(() => review.existingKeys = existing);
      }
    } on DeckFailure catch (failure) {
      _showDeckFailure(failure);
    }
  }

  void _cancel() {
    if (_stage case _Extracting(:final cancel)) cancel.complete();
    Navigator.of(context).pop();
  }

  /// Offers the camera and the library again; a cancel leaves the screen as
  /// it was.
  Future<void> _retake() async {
    final stage = await _choosePhoto(context, widget.photos);
    if (stage != null && mounted) _start(stage);
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await widget.photos.openSettings()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsNotOpened)));
    }
  }

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
