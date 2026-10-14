import 'package:flutter/material.dart';

import '../../shared/l10n/app_localizations.dart';
import 'failure.dart';

/// The message a user reads for [failure].
String describeFailure(AppLocalizations l10n, DeckFailure failure) =>
    switch (failure) {
      StorageFailure() => l10n.storageFailure,
      UnreadableCard() => l10n.unreadableCard,
    };

/// Runs [action]; a [DeckFailure] it raises is shown to the user in a snack
/// bar. Any other exception propagates.
Future<void> reportingFailure(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    await action();
  } on DeckFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeFailure(l10n, failure))),
    );
  }
}

/// The message for an error a provider holds: a [DeckFailure] is described;
/// anything else is rethrown, since no user message can explain it.
String describeProviderError(
  AppLocalizations l10n,
  Object error,
  StackTrace stackTrace,
) => switch (error) {
  DeckFailure() => describeFailure(l10n, error),
  _ => Error.throwWithStackTrace(error, stackTrace),
};
