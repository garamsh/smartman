import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_list_row.dart';
import '../../design/app_section_label.dart';
import '../../design/app_sheet.dart';
import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../design/theme_choice.dart';
import '../../l10n/app_localizations.dart';
import 'account_avatar.dart';
import 'account_data.dart';
import 'account_service.dart';
import 'account_state.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'legal.dart';
import 'providers.dart';

/// Shows the signed-in account with [syncStatus] under its email, signs it
/// out and deletes it; and the theme the app is drawn in.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({
    super.key,
    required this.syncStatus,
    required this.studySetting,
  });

  /// Where sync stands, as its caller draws it.
  final Widget syncStatus;

  /// The daily study minutes' row, as its caller draws it, under "공부".
  final Widget studySetting;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

/// The account action under way, whose row shows progress.
enum _Action { signingOut, deleting }

class _AccountScreenState extends ConsumerState<AccountScreen> {
  _Action? _busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountStateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.s8,
          AppSpace.gutter,
          AppSpace.s24,
        ),
        children: [
          // The gate leaves this screen once no account is signed in.
          if (state case SignedIn(:final email)) ...[
            _ProfileCard(email: email, syncStatus: widget.syncStatus),
            const SizedBox(height: AppSpace.sectionGap),
          ],
          AppSectionLabel(l10n.settingsStudy),
          widget.studySetting,
          const SizedBox(height: AppSpace.sectionGap),
          AppSectionLabel(l10n.displaySection),
          const _ThemeRow(),
          const SizedBox(height: AppSpace.sectionGap),
          AppSectionLabel(l10n.accountSection),
          AppListRow(
            title: l10n.signOut,
            trailing: _busy == _Action.signingOut
                ? _Progress(l10n.signingOut)
                : null,
            onTap: _busy != null || state is! SignedIn ? null : _signOut,
          ),
          AppListRow(
            title: l10n.deleteAccount,
            subtitle: l10n.deleteAccountNote,
            destructive: true,
            trailing: _busy == _Action.deleting
                ? _Progress(l10n.deletingAccount)
                : null,
            onTap: _busy != null || state is! SignedIn ? null : _deleteAccount,
          ),
          const SizedBox(height: AppSpace.s40),
          const _Footer(),
        ],
      ),
    );
  }

  /// Pushes unsynced changes, and asks before signing out when some did not
  /// arrive; then signs out and clears the device's data.
  Future<void> _signOut() async {
    final data = ref.read(accountDataProvider);
    final service = ref.read(accountServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = _Action.signingOut);
    try {
      if (!await data.push()) {
        if (!mounted || !await _confirmUnsynced()) return;
      }
      await _endSession(service, data, messenger, l10n);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Asks before deleting the account; then deletes it, signs out and clears
  /// the device's data, without pushing first.
  Future<void> _deleteAccount() async {
    final data = ref.read(accountDataProvider);
    final service = ref.read(accountServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await showAppConfirm(
      context,
      title: l10n.deleteAccountTitle,
      consequence: l10n.deleteAccountBody,
      confirmLabel: l10n.delete,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = _Action.deleting);
    try {
      try {
        await service.deleteAccount();
      } on AccountFailure catch (failure) {
        messenger.showSnackBar(
          SnackBar(content: Text(describeDeletionFailure(l10n, failure))),
        );
        return;
      }
      await _endSession(service, data, messenger, l10n);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Signs out, then clears the device's data. Signing out makes the gate
  /// close this screen, so nothing here may depend on it staying mounted.
  static Future<void> _endSession(
    AccountService service,
    AccountData data,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) async {
    try {
      await service.signOut();
    } on AccountFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeAccountFailure(l10n, failure))),
      );
    }
    // A failed sign-out still ends the session on the device.
    if (service.state is! SignedIn) {
      try {
        await data.clear();
      } on AccountDataNotCleared {
        messenger.showSnackBar(SnackBar(content: Text(l10n.dataNotCleared)));
      }
    }
  }

  /// Whether the user signs out although some changes are not synced.
  Future<bool> _confirmUnsynced() async {
    final l10n = AppLocalizations.of(context);
    return showAppConfirm(
      context,
      title: l10n.unsyncedChangesTitle,
      consequence: l10n.unsyncedChangesBody,
      confirmLabel: l10n.signOutAnyway,
    );
  }
}

/// The progress shown in the row of the action under way.
class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppSpace.s24,
    child: CircularProgressIndicator(semanticsLabel: label),
  );
}

/// The signed-in account on a card: an avatar with the email's initial, the
/// email, and where sync stands.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.email, required this.syncStatus});

  final String? email;
  final Widget syncStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s20),
        child: Row(
          spacing: AppSpace.s16,
          children: [
            const AccountAvatar(size: AppSize.avatar),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpace.s4,
                children: [
                  Text(email ?? l10n.signedIn, style: AppType.bodyStrong),
                  syncStatus,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The screen's foot: the mascot, faint, the app's version, and the links to
/// the terms and the privacy policy.
class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      spacing: AppSpace.s8,
      children: [
        const Opacity(opacity: 0.5, child: Mascot(size: AppSize.mascotSmall)),
        Text(
          l10n.appVersion(ref.watch(appVersionProvider)),
          style: AppType.caption.copyWith(color: AppColors.of(context).muted),
        ),
        const LegalLinksRow(),
      ],
    );
  }
}

/// The theme the app is drawn in, on a row: following the system, light or
/// dark, applied at once.
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppRowSurface(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s12),
        child: SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(l10n.themeSystem),
            ),
            ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
            ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
          ],
          selected: {ref.watch(themeModeProvider)},
          showSelectedIcon: false,
          onSelectionChanged: (choice) =>
              ref.read(themeModeProvider.notifier).choose(choice.single),
        ),
      ),
    );
  }
}
