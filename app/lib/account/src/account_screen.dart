import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import 'account_service.dart';
import 'account_state.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';

/// Shows whether the user is signed in, and signs them in or out.
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: switch (state) {
              SignedOut() => [
                Text(l10n.signedOutBody, textAlign: TextAlign.center),
                if (_busy)
                  CircularProgressIndicator(semanticsLabel: l10n.signingIn)
                else
                  FilledButton(
                    onPressed: () => _run((service) => service.signIn()),
                    child: Text(l10n.signInWithGoogle),
                  ),
              ],
              SignedIn(:final email) => [
                Text(
                  email == null ? l10n.signedIn : l10n.signedInAs(email),
                  textAlign: TextAlign.center,
                ),
                if (_busy)
                  CircularProgressIndicator(semanticsLabel: l10n.signingOut)
                else
                  OutlinedButton(
                    onPressed: () => _run((service) => service.signOut()),
                    child: Text(l10n.signOut),
                  ),
              ],
              AccountUnavailable(:final failure) => [
                Text(
                  describeAccountFailure(l10n, failure),
                  textAlign: TextAlign.center,
                ),
              ],
            },
          ),
        ),
      ),
    );
  }

  /// Runs [action] on the account service; an [AccountFailure] it raises is
  /// shown in a snack bar. Any other exception propagates.
  Future<void> _run(Future<void> Function(AccountService) action) async {
    final service = ref.read(accountServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action(service);
    } on AccountFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeAccountFailure(l10n, failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
