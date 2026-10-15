import 'package:flutter/material.dart' hide Card;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_chip.dart';
import '../../shared/ui/app_list_row.dart';
import '../../shared/ui/app_sheet.dart';
import 'detail_level.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'photo.dart';
import 'photo_source.dart';

/// A full-screen dark camera view with a page-frame guide, the deck the cards
/// go into, how much each card says, the album button and the shutter.
class CaptureView extends StatefulWidget {
  const CaptureView({
    super.key,
    required this.photos,
    required this.decks,
    required this.target,
    required this.onTarget,
    required this.level,
    required this.onLevel,
    required this.onPhoto,
    required this.onFailure,
  });

  final PhotoSource photos;
  final List<Deck> decks;

  /// The deck the cards go into; null for a new deck.
  final Deck? target;

  /// Chooses the deck the cards go into; null for a new deck.
  final ValueChanged<DeckId?> onTarget;

  final DetailLevel level;
  final ValueChanged<DetailLevel> onLevel;

  final ValueChanged<JpegPhoto> onPhoto;
  final ValueChanged<PhotoImportFailure> onFailure;

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

sealed class _Camera {
  const _Camera();
}

/// An open is in flight. [wanted] is false while the app is out of the
/// foreground, so the session it brings is closed rather than shown.
final class _Opening extends _Camera {
  const _Opening({this.wanted = true});

  final bool wanted;
}

final class _Open extends _Camera {
  const _Open(this.session);

  final CameraSession session;
}

final class _Closed extends _Camera {
  const _Closed(this.failure);

  final PhotoImportFailure failure;
}

/// Released while the app is out of the foreground; [closing] completes once
/// the session is closed.
final class _Released extends _Camera {
  const _Released(this.closing);

  final Future<void> closing;
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

  /// The camera is released while the app is out of the foreground, as
  /// `camera` leaves that to the app, and opened again when it returns. One
  /// open runs at a time: a change during one is applied when it lands.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        _release();
      case AppLifecycleState.resumed:
        _resume();
      case AppLifecycleState.detached ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        break;
    }
  }

  void _release() {
    switch (_camera) {
      case _Open(:final session):
        setState(() => _camera = _Released(session.close()));
      case _Opening():
        setState(() => _camera = const _Opening(wanted: false));
      case _Released() || _Closed():
        break;
    }
  }

  /// A failed open is tried again, so access allowed in Settings takes effect.
  void _resume() {
    switch (_camera) {
      case _Released(:final closing):
        setState(() => _camera = const _Opening());
        _open(after: closing);
      case _Closed():
        setState(() => _camera = const _Opening());
        _open();
      case _Opening():
        setState(() => _camera = const _Opening());
      case _Open():
        break;
    }
  }

  /// Opens the camera once [after] completes; `camera` keeps one camera per
  /// app, so a session still closing would otherwise close the new one.
  Future<void> _open({Future<void>? after}) async {
    await after;
    final CameraSession session;
    try {
      session = await widget.photos.openCamera();
    } on PhotoImportFailure catch (failure) {
      if (mounted) setState(() => _camera = _Closed(failure));
      return;
    }
    if (_camera case _Opening(wanted: true) when mounted) {
      setState(() => _camera = _Open(session));
    } else {
      final closing = session.close();
      if (mounted) setState(() => _camera = _Released(closing));
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
            _Opening() || _Released() => const SizedBox.shrink(),
            _Closed(:final failure) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s32),
                child: Text(
                  describePhotoImportFailure(l10n, failure),
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(color: colors.ink),
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
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: l10n.close,
                        icon: const Icon(LucideIcons.x),
                        color: colors.ink,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Center(
                          child: AppChip(
                            label: l10n.photoTarget(
                              widget.target?.name ?? l10n.newDeck,
                            ),
                            icon: LucideIcons.chevronDown,
                            onPressed: _chooseTarget,
                          ),
                        ),
                      ),
                      // Balances the close button, so the chip is centred.
                      const SizedBox(width: AppSpace.s40 + AppSpace.s8),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.s8,
                    AppSpace.gutter,
                    0,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.row),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.s12),
                      child: DetailLevelSelector(
                        level: widget.level,
                        onChanged: widget.onLevel,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (camera is! _Closed)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.s32,
                    ),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colors.surface,
                        shape: const StadiumBorder(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.s16,
                          vertical: AppSpace.s8,
                        ),
                        child: Text(
                          l10n.photoCaptureHint,
                          textAlign: TextAlign.center,
                          style: AppType.secondary.copyWith(color: colors.ink),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.s24,
                    AppSpace.s16,
                    AppSpace.s24,
                    AppSpace.s24,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton.filledTonal(
                            iconSize: 28,
                            tooltip: l10n.photoAlbum,
                            icon: const Icon(LucideIcons.images),
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
    final colors = AppColors.of(context);
    Widget check(bool chosen) => chosen
        ? Icon(LucideIcons.check, color: colors.know)
        : const SizedBox.shrink();
    final chosen = await showAppSheet<_TargetChoice>(
      context,
      builder: (context) => AppSheet(
        title: l10n.photoTargetTitle,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final deck in widget.decks)
              AppListRow(
                title: deck.name,
                onSheet: true,
                selected: deck.id == widget.target?.id,
                trailing: check(deck.id == widget.target?.id),
                onTap: () => Navigator.of(context).pop(_TargetChoice(deck.id)),
              ),
            AppListRow(
              title: l10n.newDeck,
              leading: const Icon(LucideIcons.plus),
              onSheet: true,
              selected: widget.target == null,
              trailing: check(widget.target == null),
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
