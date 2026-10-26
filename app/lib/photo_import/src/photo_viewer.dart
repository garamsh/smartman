import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'import_job.dart';

/// A photo's thumbnail, [width] by [height], drawn in a tap target at least
/// [AppSize.tapTarget] wide, that opens [photos] full screen on [index]; a
/// screen reader hears "사진 i 크게 보기". A photo not yet prepared shows a
/// plain tile and opens nothing.
class PhotoThumbnail extends StatelessWidget {
  const PhotoThumbnail({
    super.key,
    required this.photos,
    required this.index,
    required this.width,
    required this.height,
  });

  /// Every photo of the import in pick order; null where one is not
  /// prepared yet.
  final List<ImageProvider?> photos;
  final int index;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final photo = photos[index];
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.button / 2),
      child: SizedBox(
        width: width,
        height: height,
        child: photo == null
            ? ColoredBox(color: colors.hairline)
            : Image(
                image: ResizeImage.resizeIfNeeded(
                  thumbnailDecodeWidth,
                  null,
                  photo,
                ),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
      ),
    );
    if (photo == null) return ExcludeSemantics(child: tile);
    return Semantics(
      container: true,
      button: true,
      label: l10n.photoView(index + 1),
      excludeSemantics: true,
      onTap: () => showPhotoViewer(context, photos, index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showPhotoViewer(context, photos, index),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: AppSize.tapTarget,
            minHeight: AppSize.tapTarget,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: tile),
        ),
      ),
    );
  }
}

/// Opens [photos] full screen on [index], over whatever is on screen, which
/// goes on underneath.
Future<void> showPhotoViewer(
  BuildContext context,
  List<ImageProvider?> photos,
  int index,
) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    opaque: false,
    pageBuilder: (_, _, _) => PhotoViewer(photos: photos, initial: index),
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

/// The import's photos full screen, one a page in pick order: a pinch zooms
/// and a drag then pans; unzoomed, a swipe across turns the page and a swipe
/// down closes, as the close button and Android's back do. "사진 i/n" heads
/// it.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.photos, required this.initial});

  final List<ImageProvider?> photos;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  /// Whether the photo on screen is zoomed in, when a drag pans it rather
  /// than turning the page or closing.
  var _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final close = Navigator.of(context).pop;
    return Scaffold(
      backgroundColor: colors.ground,
      appBar: AppBar(
        backgroundColor: colors.ground,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            l10n.photoViewerTitle(_page + 1, widget.photos.length),
            style: AppType.headline.copyWith(color: colors.ink),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.close,
            icon: Icon(LucideIcons.x, color: colors.ink),
            onPressed: close,
          ),
        ],
      ),
      body: GestureDetector(
        onVerticalDragEnd: _zoomed
            ? null
            : (details) {
                if ((details.primaryVelocity ?? 0) > 300) close();
              },
        child: PageView.builder(
          controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.photos.length,
          onPageChanged: (page) => setState(() {
            _page = page;
            _zoomed = false;
          }),
          itemBuilder: (context, page) => _ZoomablePhoto(
            key: ValueKey(page),
            photo: widget.photos[page],
            onZoomed: (zoomed) {
              if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
            },
          ),
        ),
      ),
    );
  }
}

/// One photo, fitted to the page, that a pinch zooms up to four times;
/// [onZoomed] says whether it is zoomed in.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.photo,
    required this.onZoomed,
  });

  final ImageProvider? photo;
  final ValueChanged<bool> onZoomed;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();
  var _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) {
        setState(() => _zoomed = zoomed);
        widget.onZoomed(zoomed);
      }
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final photo = widget.photo;
    if (photo == null) {
      return Center(
        child: Text(
          l10n.photoWaiting,
          style: AppType.body.copyWith(color: colors.ink2),
        ),
      );
    }
    return InteractiveViewer(
      transformationController: _transform,
      panEnabled: _zoomed,
      maxScale: 4,
      child: SizedBox.expand(
        child: Image(
          image: photo,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
