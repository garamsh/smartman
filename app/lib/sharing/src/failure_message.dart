import '../../shared/l10n/app_localizations.dart';
import 'failure.dart';

/// The message a user reads for [failure].
String describeSharingFailure(AppLocalizations l10n, SharingFailure failure) =>
    switch (failure) {
      SharingOffline() => l10n.sharingOffline,
      SharingRejected() => l10n.sharingRejected,
      SharingFailed() => l10n.sharingFailed,
      DeckNoLongerPublic() => l10n.deckNoLongerPublic,
    };
