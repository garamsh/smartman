import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'failure_message.dart';
import 'photo_batch.dart';

/// Several photos being read: "사진 k/n 읽는 중", a bar of the photos read, and
/// one row per photo with its thumbnail and state. A photo that failed says
/// why, with a retry where sending it again can help and a way to leave it
/// out. [note] says when today's limit left photos out; the privacy note and
/// a cancel close the screen.
class ReadingView extends StatelessWidget {
  const ReadingView({
    super.key,
    required this.batch,
    required this.note,
    required this.onRetry,
    required this.onDrop,
    required this.onCancel,
  });

  final PhotoBatch batch;

  /// Why fewer photos are read than were picked; null when all are.
  final String? note;

  final ValueChanged<PhotoJob> onRetry;
  final ValueChanged<PhotoJob> onDrop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final jobs = batch.jobs;
    final read = jobs.where((job) => job.state is PhotoRead).length;
    final failed = jobs.where((job) => job.state is PhotoFailed).length;
    final busy = jobs.any(
      (job) => job.state is PhotoReading || job.state is PhotoWaiting,
    );
    final title = busy || failed == 0
        ? l10n.readingTitle(
            (read + failed + 1).clamp(1, jobs.length),
            jobs.length,
          )
        : l10n.readingFailed(failed);
    final note = this.note;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s24,
            AppSpace.gutter,
            AppSpace.s16,
          ),
          children: [
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(title, style: AppType.title),
            ),
            const SizedBox(height: AppSpace.s16),
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: jobs.isEmpty ? 0 : read / jobs.length,
                color: colors.ink,
                backgroundColor: colors.hairline,
                borderRadius: BorderRadius.circular(AppSpace.s4),
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpace.s12),
              Text(note, style: AppType.body.copyWith(color: colors.ink2)),
            ],
            const SizedBox(height: AppSpace.s20),
            for (final (i, job) in jobs.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpace.rowGap),
              _PhotoRow(
                key: ObjectKey(job),
                job: job,
                number: i + 1,
                onRetry: () => onRetry(job),
                onDrop: () => onDrop(job),
              ),
            ],
            const SizedBox(height: AppSpace.s20),
            Text(
              l10n.extractingNote,
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s8,
            AppSpace.gutter,
            AppSpace.s16,
          ),
          child: AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.cta,
            onPressed: onCancel,
          ),
        ),
      ),
    );
  }
}

/// One photo: its thumbnail, "사진 n", and its state in words with an icon,
/// read as one line; a failed one with its actions.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    super.key,
    required this.job,
    required this.number,
    required this.onRetry,
    required this.onDrop,
  });

  final PhotoJob job;
  final int number;
  final VoidCallback onRetry;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final photo = job.photo;
    final (IconData icon, Color iconColor, String status) = switch (job.state) {
      PhotoWaiting() => (LucideIcons.clock, colors.muted, l10n.photoWaiting),
      PhotoReading() => (LucideIcons.loader, colors.ink, l10n.photoReading),
      PhotoRead(:final cards) => (
        LucideIcons.check,
        colors.know,
        l10n.cardCount(cards.length),
      ),
      PhotoFailed(:final failure) => (
        LucideIcons.circleAlert,
        colors.dontKnow,
        describePhotoImportFailure(l10n, failure),
      ),
    };
    final failure = switch (job.state) {
      PhotoFailed(:final failure) => failure,
      _ => null,
    };
    return AppRowSurface(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MergeSemantics(
              child: Row(
                spacing: AppSpace.s12,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.button / 2),
                    child: SizedBox(
                      width: 48,
                      height: 64,
                      child: photo == null
                          ? ColoredBox(color: colors.hairline)
                          : Image.memory(
                              photo.bytes,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: AppSpace.s4,
                      children: [
                        Text(
                          l10n.photoNumber(number),
                          style: AppType.bodyStrong,
                        ),
                        Semantics(
                          liveRegion: failure != null,
                          child: Text(
                            status,
                            style: AppType.body.copyWith(
                              color: failure == null ? colors.ink2 : colors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: AppSize.smallIcon,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
            if (failure != null) ...[
              const SizedBox(height: AppSpace.s12),
              Row(
                spacing: AppSpace.s8,
                children: [
                  if (isRetryable(failure))
                    Expanded(
                      child: AppButton(
                        label: l10n.retry,
                        variant: AppButtonVariant.secondary,
                        onPressed: onRetry,
                      ),
                    ),
                  Expanded(
                    child: AppButton(
                      label: l10n.photoDrop,
                      variant: AppButtonVariant.secondary,
                      onPressed: onDrop,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
