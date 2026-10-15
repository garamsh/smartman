import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
import 'failure.dart';
import 'failure_message.dart';

/// What went wrong, in plain words, with a retry where sending the same photo
/// again can succeed and a retake where a new photo can.
class FailureView extends StatelessWidget {
  const FailureView({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onRetake,
  });

  final PhotoImportFailure failure;

  /// Sends the same photo again; null when that cannot help.
  final VoidCallback? onRetry;

  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onRetry = this.onRetry;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.close,
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s24),
          child: Semantics(
            liveRegion: true,
            child: Text(
              describePhotoImportFailure(l10n, failure),
              textAlign: TextAlign.center,
              style: AppType.bodyStrong,
            ),
          ),
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
          child: Row(
            spacing: AppSpace.s12,
            children: [
              if (isRetakeable(failure))
                Expanded(
                  child: AppButton(
                    label: l10n.retake,
                    variant: onRetry == null
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    size: AppButtonSize.cta,
                    onPressed: onRetake,
                  ),
                ),
              if (onRetry != null)
                Expanded(
                  child: AppButton(
                    label: l10n.retry,
                    size: AppButtonSize.cta,
                    onPressed: onRetry,
                  ),
                ),
              if (!isRetakeable(failure) && onRetry == null)
                Expanded(
                  child: AppButton(
                    label: l10n.close,
                    size: AppButtonSize.cta,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
