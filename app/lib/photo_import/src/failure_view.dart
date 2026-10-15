import 'package:flutter/material.dart';

import '../../shared/l10n/app_localizations.dart';
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
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            child: Text(
              describePhotoImportFailure(l10n, failure),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            spacing: 12,
            children: [
              if (isRetakeable(failure))
                Expanded(
                  child: onRetry == null
                      ? FilledButton(
                          onPressed: onRetake,
                          child: Text(l10n.retake),
                        )
                      : OutlinedButton(
                          onPressed: onRetake,
                          child: Text(l10n.retake),
                        ),
                ),
              if (onRetry != null)
                Expanded(
                  child: FilledButton(
                    onPressed: onRetry,
                    child: Text(l10n.retry),
                  ),
                ),
              if (!isRetakeable(failure) && onRetry == null)
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.close),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
