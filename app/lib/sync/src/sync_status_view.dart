import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_button.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'failure.dart';
import 'providers.dart';
import 'status.dart';

/// One line on where sync stands: syncing, synced, offline, or failed with a
/// retry. Shows nothing while no account is signed in.
class SyncStatusView extends ConsumerWidget {
  const SyncStatusView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(syncControllerProvider);
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return ValueListenableBuilder(
      valueListenable: controller.status,
      builder: (context, status, _) => switch (status) {
        SyncIdle() => const SizedBox.shrink(),
        Syncing() => _StatusLine(
          icon: const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          text: l10n.syncSyncing,
          color: colors.muted,
        ),
        Synced() => _StatusLine(text: l10n.syncSynced, color: colors.muted),
        SyncInterrupted(failure: SyncOffline()) => _StatusLine(
          text: l10n.syncOffline,
          color: colors.muted,
        ),
        SyncInterrupted(failure: SyncRejected() || SyncFailed()) => _StatusLine(
          text: l10n.syncFailed,
          color: colors.dontKnowText,
          action: AppButton(
            label: l10n.syncRetry,
            variant: AppButtonVariant.text,
            onPressed: controller.retry,
          ),
        ),
      },
    );
  }
}

/// A line of text read out as it changes, after a progress [icon] while
/// syncing, and an optional action. Every other state is said by its words.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    this.icon,
    required this.text,
    required this.color,
    this.action,
  });

  final Widget? icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: AppSpace.s8,
    children: [
      if (icon case final icon?) ExcludeSemantics(child: icon),
      Flexible(
        child: Semantics(
          liveRegion: true,
          child: Text(text, style: AppType.secondary.copyWith(color: color)),
        ),
      ),
      ?action,
    ],
  );
}
