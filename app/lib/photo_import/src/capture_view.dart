import 'package:flutter/material.dart' hide Card;

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'photo.dart';
import 'photo_source.dart';

/// A full-screen dark camera view with a page-frame guide, the deck the cards
/// go into, the album button and the shutter.
class CaptureView extends StatefulWidget {
  const CaptureView({
    super.key,
    required this.photos,
    required this.decks,
    required this.target,
    required this.onTarget,
    required this.onPhoto,
    required this.onFailure,
  });

  final PhotoSource photos;
  final List<Deck> decks;

  /// The deck the cards go into; null for a new deck.
  final Deck? target;

  /// Chooses the deck the cards go into; null for a new deck.
  final ValueChanged<DeckId?> onTarget;

  final ValueChanged<JpegPhoto> onPhoto;
  final ValueChanged<PhotoImportFailure> onFailure;

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

sealed class _Camera {
  const _Camera();
}

final class _Opening extends _Camera {
  const _Opening();
}

final class _Open extends _Camera {
  const _Open(this.session);

  final CameraSession session;
}

final class _Closed extends _Camera {
  const _Closed(this.failure);

  final PhotoImportFailure failure;
}

class _CaptureViewState extends State<CaptureView> with WidgetsBindingObserver {
  _Camera _camera = const _Opening();

  /// A photo is being taken or picked.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close();
    super.dispose();
  }

  /// The camera is released while the app is in the background, as `camera`
  /// leaves that to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        _close();
        setState(() => _camera = const _Opening());
      case AppLifecycleState.resumed:
        if (_camera is _Opening) _open();
      case AppLifecycleState.detached ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        break;
    }
  }

  Future<void> _open() async {
    try {
      final session = await widget.photos.openCamera();
      if (!mounted || _camera is! _Opening) {
        await session.close();
        return;
      }
      setState(() => _camera = _Open(session));
    } on PhotoImportFailure catch (failure) {
      if (mounted) setState(() => _camera = _Closed(failure));
    }
  }

  void _close() {
    if (_camera case _Open(:final session)) session.close();
  }

  Future<void> _take(Future<JpegPhoto?> Function() source) async {
    setState(() => _busy = true);
    try {
      final photo = await source();
      if (photo != null && mounted) widget.onPhoto(photo);
    } on PhotoImportFailure catch (failure) {
      if (mounted) widget.onFailure(failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: darkTheme,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final camera = _camera;
    return Scaffold(
      backgroundColor: colors.ground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          switch (camera) {
            _Open(:final session) => ClipRect(
              child: FittedBox(fit: BoxFit.cover, child: session.preview),
            ),
            _Opening() => const SizedBox.shrink(),
            _Closed(:final failure) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  describePhotoImportFailure(l10n, failure),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(color: colors.ink),
                ),
              ),
            ),
          },
          if (camera is! _Closed)
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.8,
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.ink, width: 2),
                      borderRadius: BorderRadius.circular(AppRadius.row),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: l10n.close,
                      icon: const Icon(Icons.close),
                      color: colors.ink,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Center(
                        child: ActionChip(
                          avatar: Icon(Icons.expand_more, color: colors.ink),
                          label: Text(
                            l10n.photoTarget(
                              widget.target?.name ?? l10n.newDeck,
                            ),
                          ),
                          onPressed: _chooseTarget,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const Spacer(),
                if (camera is! _Closed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.row),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          l10n.photoCaptureHint,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton.filledTonal(
                            iconSize: 28,
                            tooltip: l10n.photoAlbum,
                            icon: const Icon(Icons.photo_library_outlined),
                            onPressed: _busy
                                ? null
                                : () => _take(widget.photos.pickFromLibrary),
                          ),
                        ),
                      ),
                      _Shutter(
                        busy: _busy,
                        onPressed: switch (camera) {
                          _Open(:final session) when !_busy => () => _take(
                            session.takePicture,
                          ),
                          _ => null,
                        },
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseTarget() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await showModalBottomSheet<_TargetChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final deck in widget.decks)
              ListTile(
                title: Text(deck.name),
                selected: deck.id == widget.target?.id,
                trailing: deck.id == widget.target?.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(_TargetChoice(deck.id)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.newDeck),
              selected: widget.target == null,
              trailing: widget.target == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(const _TargetChoice(null)),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) widget.onTarget(chosen.deck);
  }
}

/// A choice in the target sheet; null [deck] is a new deck.
final class _TargetChoice {
  const _TargetChoice(this.deck);

  final DeckId? deck;
}

/// The round shutter, in the centre of the bottom row.
class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: 76,
      child: IconButton(
        tooltip: l10n.photoShutter,
        style: IconButton.styleFrom(
          backgroundColor: colors.ink,
          disabledBackgroundColor: colors.muted,
          shape: CircleBorder(
            side: BorderSide(color: colors.surface, width: 4),
          ),
        ),
        onPressed: onPressed,
        icon: busy
            ? CircularProgressIndicator(color: colors.surface)
            : const SizedBox.shrink(),
      ),
    );
  }
}
