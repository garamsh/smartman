import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'account_data.dart';
import 'account_state.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';

/// Shows the signed-in account and signs it out; and the theme the app is
/// drawn in.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountStateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      bottomNavigationBar: const SafeArea(child: _ThemeSection()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: switch (state) {
              SignedIn(:final email) => [
                Text(
                  email == null ? l10n.signedIn : l10n.signedInAs(email),
                  textAlign: TextAlign.center,
                ),
                ref.watch(syncStatusProvider)(),
                if (_busy)
                  CircularProgressIndicator(semanticsLabel: l10n.signingOut)
                else
                  OutlinedButton(
                    onPressed: _signOut,
                    child: Text(l10n.signOut),
                  ),
              ],
              // The gate leaves this screen once no account is signed in.
              SignedOut() || AccountUnavailable() => [],
            },
          ),
        ),
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
    setState(() => _busy = true);
    try {
      if (!await data.push()) {
        if (!mounted || !await _confirmUnsynced()) return;
      }
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Whether the user signs out although some changes are not synced.
  Future<bool> _confirmUnsynced() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.unsyncedChangesTitle),
        content: Text(l10n.unsyncedChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.signOutAnyway),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

/// The "화면" section: following the system, light or dark, applied at once.
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            l10n.displaySection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(l10n.themeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l10n.themeLight),
              ),
              ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
            ],
            selected: {ref.watch(themeModeProvider)},
            showSelectedIcon: false,
            onSelectionChanged: (choice) =>
                ref.read(themeModeProvider.notifier).choose(choice.single),
          ),
        ],
      ),
    );
  }
}
