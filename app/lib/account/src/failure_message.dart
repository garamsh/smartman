import '../../shared/l10n/app_localizations.dart';
import 'failure.dart';

/// The message a user reads for [failure].
String describeAccountFailure(AppLocalizations l10n, AccountFailure failure) =>
    switch (failure) {
      AccountOffline() => l10n.accountOffline,
      AccountMisconfigured() => l10n.accountMisconfigured,
      AccountRejected() => l10n.accountRejected,
    };

/// The message a user reads when deleting the account failed with [failure].
String describeDeletionFailure(AppLocalizations l10n, AccountFailure failure) =>
    switch (failure) {
      AccountOffline() => l10n.accountOffline,
      AccountMisconfigured() => l10n.accountMisconfigured,
      AccountRejected() => l10n.deleteAccountRejected,
    };
