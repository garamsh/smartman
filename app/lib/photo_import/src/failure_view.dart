import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'failure.dart';
import 'failure_message.dart';

/// What went wrong, in plain words, with a retry where sending the same photo
/// again can succeed, a retake where a new photo can, and the way to Settings
/// where access was refused. The top bar's close is the one way out.
class FailureView extends StatelessWidget {
  const FailureView({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onRetake,
    required this.retakeLabel,
    required this.onOpenSettings,
  });

  final PhotoImportFailure failure;

  /// Sends the same photo again; null when that cannot help.
  final VoidCallback? onRetry;

  final VoidCallback onRetake;

  /// What the retake is called: "다시 찍기", or "다른 사진 고르기" for a photo
  /// from the album.
  final String retakeLabel;

  /// Opens this app's page in the system settings; null when access was not
  /// what failed.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onRetry = this.onRetry;
    final onOpenSettings = this.onOpenSettings;
    final primaryElsewhere = onRetry != null || onOpenSettings != null;
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
      bottomNavigationBar: !isRetakeable(failure) && !primaryElsewhere
          ? null
          : SafeArea(
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
                          label: retakeLabel,
                          variant: primaryElsewhere
                              ? AppButtonVariant.secondary
                              : AppButtonVariant.primary,
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
                    if (onOpenSettings != null)
                      Expanded(
                        child: AppButton(
                          label: l10n.openSettings,
                          size: AppButtonSize.cta,
                          onPressed: onOpenSettings,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
