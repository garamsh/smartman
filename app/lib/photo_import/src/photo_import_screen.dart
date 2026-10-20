import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../deck/deck.dart';
import '../../design/app_list_row.dart';
import '../../design/app_sheet.dart';
import '../../l10n/app_localizations.dart';
import 'extracting_view.dart';
import 'extraction_client.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'failure_view.dart';
import 'photo.dart';
import 'import_list.dart';
import 'import_list_view.dart';
import 'photo_batch.dart';
import 'photo_source.dart';
import 'reading_view.dart';

/// The keys the storage given to photo import must be opened to cache.
const photoImportStorageKeys = {_formsKey};

/// The section forms the device remembers, per deck and section, as JSON.
const _formsKey = 'photoImportForms';

/// Every deck, kept current, for the target chip.
final _decksProvider = StreamProvider.autoDispose<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).watchDecks(),
);

/// Takes a photo with the camera, or picks up to [maxPhotosPerImport] from
/// the library, as [origin] names, over [context], and opens the screen that
/// extracts candidate cards from them and saves the ones the user keeps into
/// [deck], or into a new deck when it is null. [preferences], opened to cache
/// [photoImportStorageKeys], keeps the form each section's cards took, per
/// deck and topic. A cancel opens nothing. Nothing is written before the
/// user confirms; resolves to the [Deck] saved into, or to null.
Future<Deck?> importFromPhoto(
  BuildContext context, {
  required DeckId? deck,
  required PhotoOrigin origin,
  required ExtractionClient client,
  required PhotoSource photos,
  required SharedPreferencesWithCache preferences,
}) async {
  final navigator = Navigator.of(context);
  final first = await _takePhotos(photos, origin, maxPhotosPerImport);
  if (first == null) return null;
  return navigator.push(
    MaterialPageRoute<Deck>(
      builder: (_) => _PhotoImportScreen(
        first: first,
        deck: deck,
        origin: origin,
        client: client,
        photos: photos,
        preferences: preferences,
      ),
    ),
  );
}

/// Takes one photo by [origin] from [photos], or up to [limit] from the
/// album. Resolves to extracting one photo, to reading several, or to the
/// failure that came instead; null when the camera or the picker is
/// cancelled.
Future<_Stage?> _takePhotos(
  PhotoSource photos,
  PhotoOrigin origin,
  int limit,
) async {
  try {
    final picked = switch (origin) {
      PhotoOrigin.camera => switch (await photos.takePhoto()) {
        final photo? => [Future.value(photo)],
        null => null,
      },
      PhotoOrigin.album => await photos.pickFromLibrary(limit: limit),
    };
    return switch (picked) {
      null || [] => null,
      [final one] => _Extracting(await one),
      final several => _Picked(several),
    };
  } on PhotoImportFailure catch (failure) {
    return _Failed(failure, null);
  }
}

class _PhotoImportScreen extends ConsumerStatefulWidget {
  const _PhotoImportScreen({
    required this.first,
    required this.deck,
    required this.origin,
    required this.client,
    required this.photos,
    required this.preferences,
  });

  /// The photo to extract from, or the failure that came instead of one.
  final _Stage first;

  final DeckId? deck;

  /// Where the photo came from, which a retake goes back to.
  final PhotoOrigin origin;
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

/// Several photos picked, before today's limit is read.
final class _Picked extends _Stage {
  const _Picked(this.photos);

  final List<Future<JpegPhoto>> photos;
}

/// Several photos being read, or photos being added to [list].
final class _Reading extends _Stage {
  _Reading(this.batch, this.list, this.note);

  final PhotoBatch batch;

  /// The list the photos are added to; null for the import's first photos.
  final ImportList? list;

  /// Why fewer photos are read than were picked; null when all are.
  final String? note;
}

final class _Listing extends _Stage {
  const _Listing(this.list);

  final ImportList list;
}

class _PhotoImportScreenState extends ConsumerState<_PhotoImportScreen> {
  late _Stage _stage = widget.first;

  /// The deck the cards go into; null for a new deck.
  late DeckId? _target = widget.deck;

  bool _saving = false;

  /// The photos the list's rows come from, in the list's order.
  final _photos = <JpegPhoto>[];

  /// The section forms the device remembers.
  late final _forms = SectionForms.parse(
    widget.preferences.getString(_formsKey),
  );

  @override
  void initState() {
    super.initState();
    _begin(_stage);
  }

  @override
  void dispose() {
    switch (_stage) {
      case _Extracting(:final cancel) when !cancel.isCompleted:
        cancel.complete();
      case _Reading(:final batch):
        batch.cancel();
      case _:
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
    final retakeLabel = switch (_retakeOrigin) {
      PhotoOrigin.camera => l10n.retake,
      PhotoOrigin.album when _origin == PhotoOrigin.camera => l10n.photoAlbum,
      PhotoOrigin.album => l10n.pickAnother,
    };
    return switch (_stage) {
      _Extracting(:final photo) => ExtractingView(
        photo: photo,
        onCancel: _cancel,
      ),
      // Today's limit is being read; a blank screen for that moment.
      _Picked() => const Scaffold(),
      _Reading(:final batch, :final note) => ReadingView(
        batch: batch,
        note: note,
        onRetry: batch.retry,
        onDrop: batch.drop,
        onCancel: _cancel,
      ),
      _Failed(:final failure, :final photo) => FailureView(
        failure: failure,
        onRetry: photo == null || !isRetryable(failure)
            ? null
            : () => _start(_Extracting(photo)),
        onRetake: _retake,
        retakeLabel: retakeLabel,
        onOpenSettings: failure is PhotoAccessDenied ? _openSettings : null,
      ),
      _Listing(:final list) => ImportListView(
        list: list,
        photos: _photos,
        decks: decks.value ?? const [],
        target: target,
        onTarget: (deck) => _chooseTarget(list, deck),
        saving: _saving,
        onChanged: () => setState(() {}),
        onCancel: () => Navigator.of(context).pop(),
        // A retake replaces a single photo; with several, photos are added.
        onRetake: list.photoCount == 1 ? _retake : null,
        retakeLabel: retakeLabel,
        onAddPhotos: _photos.length < maxPhotosPerImport
            ? () => _addPhotos(list)
            : null,
        onSave: () => _save(list),
      ),
    };
  }

  /// Shows [stage], and starts what it waits for.
  void _start(_Stage stage) {
    setState(() => _stage = stage);
    _begin(stage);
  }

  void _begin(_Stage stage) {
    switch (stage) {
      case final _Extracting stage:
        _extract(stage);
      case _Picked(:final photos):
        _read(photos, null);
      case _:
    }
  }

  Future<void> _extract(_Extracting stage) async {
    bool current() => mounted && identical(_stage, stage);
    try {
      final cards = await widget.client.extract(
        stage.photo,
        cancel: stage.cancel.future,
      );
      if (cards == null || !current()) return;
      final list = ImportList(cards, await _existingKeys(_target));
      if (_target case final deck?) _forms.applyTo(list, deck);
      _photos
        ..clear()
        ..add(stage.photo);
      if (current()) setState(() => _stage = _Listing(list));
    } on PhotoImportFailure catch (failure) {
      if (current()) setState(() => _stage = _Failed(failure, stage.photo));
    }
  }

  /// Reads [photos] at most [photosReadAtOnce] at a time, into [list], or
  /// into a new list when it is null. Today's limit is read first: past it,
  /// only the first photos it leaves are read, which a note says; with none
  /// left, the limit's failure shows, or a snack bar over [list]. Where the
  /// limit cannot be read, every photo is read and each refusal shows on its
  /// photo.
  Future<void> _read(List<Future<JpegPhoto>> photos, ImportList? list) async {
    final allowance = await widget.client.allowance();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    var take = photos;
    String? note;
    if (allowance case (:final dailyLimit, :final used)) {
      final left = dailyLimit - used;
      if (left <= 0) {
        final failure = DailyLimitReached(dailyLimit: dailyLimit);
        if (list == null) {
          setState(() => _stage = _Failed(failure, null));
        } else {
          setState(() => _stage = _Listing(list));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(describePhotoImportFailure(l10n, failure))),
          );
        }
        return;
      }
      if (left < photos.length) {
        take = photos.take(left).toList();
        note = l10n.photosLeftToday(left);
      }
    }
    late final _Reading stage;
    final batch = PhotoBatch(
      take,
      extract: widget.client.extract,
      onChanged: () {
        if (mounted && identical(_stage, stage)) {
          setState(() {});
          _finish(stage);
        }
      },
    );
    stage = _Reading(batch, list, note);
    setState(() => _stage = stage);
    batch.start();
  }

  /// Once every photo of [stage] is read or left out, adds their cards to
  /// the list, photo by photo, and shows it; with none, goes back to the
  /// list, or closes the screen when there is none.
  Future<void> _finish(_Reading stage) async {
    final batch = stage.batch;
    if (!batch.finished) return;
    if (batch.jobs.isEmpty) {
      if (stage.list case final list?) {
        setState(() => _stage = _Listing(list));
      } else {
        Navigator.of(context).pop();
      }
      return;
    }
    final read = [
      for (final job in batch.jobs)
        switch (job) {
          PhotoJob(state: PhotoRead(:final cards), photo: final photo?) => (
            photo,
            cards,
          ),
          _ => throw StateError('A finished batch holds only read photos.'),
        },
    ];
    final keys = stage.list?.existingKeys ?? await _existingKeys(_target);
    if (!mounted || !identical(_stage, stage)) return;
    final ImportList list;
    final added = <ImportSection>[];
    var rest = read;
    if (stage.list case final existing?) {
      list = existing;
    } else {
      list = ImportList(read.first.$2, keys);
      added.addAll(list.sections);
      rest = read.skip(1).toList();
    }
    for (final (_, cards) in rest) {
      added.addAll(list.addPhoto(cards));
    }
    _photos.addAll([for (final (photo, _) in read) photo]);
    if (_target case final deck?) {
      _forms.applyTo(list, deck, sections: added);
    }
    setState(() => _stage = _Listing(list));
  }

  /// Takes more photos into [list], from the camera or the album, up to
  /// [maxPhotosPerImport] in all; a cancel leaves the list as it was.
  Future<void> _addPhotos(ImportList list) async {
    final l10n = AppLocalizations.of(context);
    final origin = await showAppSheet<PhotoOrigin>(
      context,
      builder: (context) => AppSheet(
        title: l10n.addPhotos,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (origin, label, icon) in [
              (PhotoOrigin.camera, l10n.photoCamera, LucideIcons.camera),
              (PhotoOrigin.album, l10n.photoAlbum, LucideIcons.images),
            ])
              AppListRow(
                title: label,
                leading: Icon(icon),
                onSheet: true,
                onTap: () => Navigator.of(context).pop(origin),
              ),
          ],
        ),
      ),
    );
    if (origin == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final List<Future<JpegPhoto>>? picked;
    try {
      picked = switch (origin) {
        PhotoOrigin.camera => switch (await widget.photos.takePhoto()) {
          final photo? => [Future.value(photo)],
          null => null,
        },
        PhotoOrigin.album => await widget.photos.pickFromLibrary(
          limit: maxPhotosPerImport - _photos.length,
        ),
      };
    } on PhotoImportFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describePhotoImportFailure(l10n, failure))),
      );
      return;
    }
    if (picked == null || picked.isEmpty || !mounted) return;
    await _read(picked, list);
  }

  /// The card keys [deck] holds; none for a new deck, or when they cannot be
  /// read, which a snack bar says.
  Future<Set<CardKey>> _existingKeys(DeckId? deck) async {
    try {
      return await _keysOf(ref.read(deckRepositoryProvider), deck);
    } on DeckFailure catch (failure) {
      _showDeckFailure(failure);
      return const {};
    }
  }

  /// The card keys [deck] holds; none for a new deck.
  static Future<Set<CardKey>> _keysOf(
    DeckRepository repository,
    DeckId? deck,
  ) async => deck == null
      ? const {}
      : {for (final card in await repository.listCards(deck)) card.cardKey};

  /// Saves into [deck] from now on, with the rows checked against its keys
  /// once they are read, and the forms it remembers applied.
  Future<void> _chooseTarget(ImportList list, DeckId? deck) async {
    setState(() => _target = deck);
    final existing = await _existingKeys(deck);
    if (mounted && _target == deck) {
      setState(() {
        list.existingKeys = existing;
        if (deck != null) _forms.applyTo(list, deck);
      });
    }
  }

  /// Stops what is being read. The first photos' cancel closes the screen;
  /// photos being added go back to the list without them.
  void _cancel() {
    switch (_stage) {
      case _Extracting(:final cancel):
        cancel.complete();
      case _Reading(:final batch, :final list):
        batch.cancel();
        if (list != null) {
          setState(() => _stage = _Listing(list));
          return;
        }
      case _:
    }
    Navigator.of(context).pop();
  }

  /// Where the photo on screen came from; a retake goes back there.
  late PhotoOrigin _origin = widget.origin;

  /// Where a retake takes the next photo from: where the last one came from,
  /// or the album where the camera cannot open.
  PhotoOrigin get _retakeOrigin => switch (_stage) {
    _Failed(failure: CameraUnavailable()) => PhotoOrigin.album,
    _ => _origin,
  };

  /// Takes another photo from [_retakeOrigin] in place of the one there is;
  /// a cancel leaves the screen as it was.
  Future<void> _retake() async {
    final origin = _retakeOrigin;
    final stage = await _takePhotos(widget.photos, origin, 1);
    if (stage != null && mounted) {
      _origin = origin;
      _photos.clear();
      _start(stage);
    }
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await widget.photos.openSettings()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsNotOpened)));
    }
  }

  Future<void> _save(ImportList list) async {
    final l10n = AppLocalizations.of(context);
    final AddTarget target;
    if (_target case final deck?) {
      target = AddToDeck(deck);
    } else {
      final name = await showNameSheet(
        context,
        title: l10n.newDeck,
        action: l10n.create,
      );
      if (name == null || !mounted) return;
      target = AddToNewDeck(name);
    }
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(deckRepositoryProvider)
          .addCards(target, list.toImport());
      // The cards are saved; a form that cannot be stored says so and is
      // used only until the app closes.
      try {
        await widget.preferences.setString(
          _formsKey,
          _forms.remember(list, result.deck.id),
        );
      } on Exception catch (cause) {
        _showDeckFailure(StorageFailure(cause));
      }
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
