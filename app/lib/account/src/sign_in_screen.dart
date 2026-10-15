import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
import 'account_state.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';

/// The app's welcome while no account is signed in: its name, what it does,
/// and Google sign-in; or, when this build cannot sign anyone in, why.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final state = ref.watch(accountStateProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.s24,
            AppSpace.gutter,
            AppSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s12,
            children: [
              const Spacer(),
              Semantics(
                header: true,
                child: Text(l10n.appTitle, style: AppType.display),
              ),
              Text(
                l10n.welcomeBody,
                style: AppType.body.copyWith(color: colors.muted),
              ),
              const Spacer(),
              ...switch (state) {
                AccountUnavailable(:final failure) => [
                  Text(
                    describeAccountFailure(l10n, failure),
                    textAlign: TextAlign.center,
                    style: AppType.body,
                  ),
                ],
                _ when _busy => [
                  Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: l10n.signingIn,
                    ),
                  ),
                ],
                _ => [
                  AppButton(
                    label: l10n.signInWithGoogle,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.cta,
                    onPressed: _signIn,
                  ),
                  // Apple sign-in (M4b) fills this slot.
                  AppButton(
                    label: l10n.signInWithAppleSoon,
                    size: AppButtonSize.cta,
                    onPressed: null,
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  /// Signs in with Google; an [AccountFailure] is shown in a snack bar. Any
  /// other exception propagates.
  Future<void> _signIn() async {
    final service = ref.read(accountServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await service.signIn();
    } on AccountFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeAccountFailure(l10n, failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
