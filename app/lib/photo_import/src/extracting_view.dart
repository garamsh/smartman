import 'package:flutter/material.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'photo.dart';

/// The photo, "카드를 찾고 있어요", an indeterminate bar and skeleton rows
/// while the cards are extracted, with the privacy note and a cancel.
class ExtractingView extends StatelessWidget {
  const ExtractingView({
    super.key,
    required this.photo,
    required this.onCancel,
  });

  final JpegPhoto photo;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          children: [
            Row(
              spacing: 16,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  child: Image.memory(
                    photo.bytes,
                    width: 72,
                    height: 96,
                    fit: BoxFit.cover,
                    semanticLabel: l10n.photoThumbnail,
                  ),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      l10n.extractingTitle,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(semanticsLabel: l10n.extractingTitle),
            const SizedBox(height: 20),
            for (var row = 0; row < 4; row++) const _SkeletonRow(),
            const SizedBox(height: 12),
            Text(
              l10n.extractingNote,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: OutlinedButton(onPressed: onCancel, child: Text(l10n.cancel)),
        ),
      ),
    );
  }
}

/// A placeholder row, front and back, that shimmers unless reduce motion is
/// on.
class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow();

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
      _shimmer.value = 0;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget bar(double widthFactor) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: colors.hairline,
          borderRadius: BorderRadius.circular(7),
        ),
      ),
    );
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.4).animate(_shimmer),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.row),
          ),
          child: Row(
            spacing: 16,
            children: [
              Expanded(child: bar(0.7)),
              Expanded(child: bar(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
