// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'smartman';

  @override
  String get newDeck => 'New deck';

  @override
  String get deckActions => 'Deck actions';

  @override
  String get renameDeck => 'Rename deck';

  @override
  String get deleteDeck => 'Delete deck';

  @override
  String deleteDeckTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String deleteDeckBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count cards will be deleted too.',
      one: 'Its 1 card will be deleted too.',
      zero: 'This deck has no cards.',
    );
    return '$_temp0';
  }

  @override
  String get deckName => 'Deck name';

  @override
  String get deckNameRequired => 'Enter a name';

  @override
  String get noCards => 'No cards yet. Add a card to start.';

  @override
  String get newCard => 'Add card';

  @override
  String get editCard => 'Edit card';

  @override
  String get deleteCard => 'Delete card';

  @override
  String get cardFront => 'Question';

  @override
  String get cardBack => 'Answer';

  @override
  String get cardSideRequired => 'Enter some text';

  @override
  String get duplicateTitle => 'This deck already has this card';

  @override
  String get duplicateBody => 'Case and spacing are ignored when comparing.';

  @override
  String get openExistingCard => 'Open existing card';

  @override
  String get addAnyway => 'Add anyway';

  @override
  String get saveAnyway => 'Save anyway';

  @override
  String unsupportedContent(String type) {
    return '[Content this version cannot show: $type]';
  }

  @override
  String get storageFailure =>
      'Couldn\'t read or write the device\'s storage. Please try again.';

  @override
  String get unreadableCard => 'A card in this deck can\'t be read.';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String decksSelected(int count) {
    return '$count selected';
  }

  @override
  String studySelected(int count) {
    return 'Study ($count)';
  }

  @override
  String todayCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards for today',
      one: '1 card for today',
    );
    return '$_temp0';
  }

  @override
  String get studyAll => 'Study all';

  @override
  String get know => 'Know';

  @override
  String get dontKnow => 'Don\'t know';

  @override
  String get close => 'Close';

  @override
  String studyProgress(int answered, int total) {
    return '$answered/$total';
  }

  @override
  String studyProgressSemantics(int answered, int total) {
    return '$answered of $total cards answered';
  }

  @override
  String currentCardSemantics(String front) {
    return 'Front: $front';
  }

  @override
  String currentCardRevealedSemantics(String front, String back) {
    return 'Front: $front. Back: $back';
  }

  @override
  String get showAnswer => 'show the answer';

  @override
  String get hideAnswer => 'hide the answer';

  @override
  String previousCardSemantics(
    String front,
    String back,
    String answer,
    String changed,
  ) {
    String _temp0 = intl.Intl.selectLogic(changed, {
      'yes': '. Changed',
      'other': '',
    });
    return 'Front: $front. Back: $back. Answer: $answer$_temp0';
  }

  @override
  String get toggleAnswer => 'change the answer';

  @override
  String get showWholeCard => 'show the whole card';

  @override
  String get answerChanged => 'Changed';

  @override
  String get sessionSummaryTitle => 'You\'ve finished today\'s cards';

  @override
  String get nothingToStudy => 'Nothing to study right now.';

  @override
  String get answerNotSaved =>
      'Couldn\'t save your answer on this device. This card\'s schedule did not change.';

  @override
  String get schedulingFailure =>
      'Couldn\'t work out this card\'s next review. Its schedule did not change.';

  @override
  String get account => 'Account';

  @override
  String get accountTitle => 'Account';

  @override
  String get welcomeBody =>
      'Swipe to answer,\nand meet each card again just before you forget';

  @override
  String get signInWithGoogle => 'Continue with Google';

  @override
  String get signInWithAppleSoon => 'Continue with Apple · Coming soon';

  @override
  String get signingIn => 'Signing in';

  @override
  String get signedIn => 'Signed in';

  @override
  String get signOut => 'Sign out';

  @override
  String get signingOut => 'Signing out';

  @override
  String get accountOffline =>
      'Couldn\'t reach the server. Check your internet connection.';

  @override
  String get accountMisconfigured =>
      'Sign-in isn\'t set up correctly in this app, so you can\'t sign in.';

  @override
  String get accountRejected => 'Google sign-in was refused. Please try again.';

  @override
  String get accountSection => 'Account';

  @override
  String get displaySection => 'Display';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String todayBreakdown(int review, int fresh, int minutes) {
    return '$review to review · $fresh new · about $minutes min';
  }

  @override
  String myDecks(int count) {
    return 'My decks $count';
  }

  @override
  String get selectHint => 'Long-press to select several decks';

  @override
  String cardCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
    );
    return '$_temp0';
  }

  @override
  String todayChip(int count) {
    return 'Today $count';
  }

  @override
  String get createFromPhoto => 'Create from photo';

  @override
  String get addFromPhoto => 'Add from photo';

  @override
  String get backlogPaused =>
      'New cards wait until you catch up on your reviews.';

  @override
  String studyCount(int count) {
    return 'Study · $count';
  }

  @override
  String get searchCards => 'Search';

  @override
  String get noMatches => 'No card matches. Try other words.';

  @override
  String get saveAndNext => 'Save and next card';

  @override
  String get deleteCardTitle => 'Delete this card?';

  @override
  String get deleteCardBody => 'Its study history is deleted with it.';

  @override
  String get unsyncedChangesTitle => 'Some changes aren\'t synced';

  @override
  String get unsyncedChangesBody =>
      'Signing out removes them from this device, and your other devices won\'t have them.';

  @override
  String get signOutAnyway => 'Sign out anyway';

  @override
  String get dataNotCleared =>
      'Couldn\'t remove this device\'s data. It\'s removed when another account signs in.';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountNote =>
      'Deleting your account removes your cards and history from the server and this device. You can\'t undo this.';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'Your decks, cards and study history are removed from the server and this device, while decks others copied and your Google account stay.';

  @override
  String get deletingAccount => 'Deleting account';

  @override
  String get deleteAccountRejected =>
      'Couldn\'t delete your account. Try again.';

  @override
  String get syncSyncing => 'Syncing';

  @override
  String get syncSynced => 'Synced';

  @override
  String get syncOffline => 'Offline · syncs when connected';

  @override
  String get syncFailed => 'Couldn\'t sync';

  @override
  String get syncRetry => 'Try again';

  @override
  String get photoCaptureHint =>
      'Fit one page of a vocabulary book or textbook inside the frame';

  @override
  String photoTarget(String name) {
    return 'Add to · $name';
  }

  @override
  String get photoTargetTitle => 'Add to';

  @override
  String get photoAlbum => 'Choose from album';

  @override
  String get photoShutter => 'Take photo';

  @override
  String get cameraDenied =>
      'The app isn\'t allowed to use the camera. Allow it in Settings, or choose a photo from your album.';

  @override
  String get cameraUnavailable =>
      'Couldn\'t open the camera. Choose a photo from your album.';

  @override
  String get photoThumbnail => 'Your photo';

  @override
  String get extractingTitle => 'Finding cards';

  @override
  String get extractingNote =>
      'Your photo is used only to make cards and isn\'t kept on the server';

  @override
  String reviewTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count cards',
      one: 'Found 1 card',
    );
    return '$_temp0';
  }

  @override
  String reviewHint(String deck) {
    return 'Tap to edit, and uncheck the cards to leave out · $deck';
  }

  @override
  String get detailLevelLabel => 'What each card says';

  @override
  String get detailLevelSimple => 'Simple';

  @override
  String get detailLevelBasic => 'Basic';

  @override
  String get detailLevelDetailed => 'Detailed';

  @override
  String get candidateEdited => 'Edited';

  @override
  String reviewDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards already in the deck',
      one: '1 card already in the deck',
    );
    return '$_temp0';
  }

  @override
  String get includeCard => 'Include';

  @override
  String get duplicateSkip => 'Skip';

  @override
  String get duplicateMergeBack => 'Merge back';

  @override
  String get duplicateAddNew => 'Add as new';

  @override
  String get retake => 'Retake';

  @override
  String get retry => 'Try again';

  @override
  String addCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count cards',
      one: 'Add 1 card',
    );
    return '$_temp0';
  }

  @override
  String get extractionOffline =>
      'You\'re offline. Check your connection and try again.';

  @override
  String get photoRefused =>
      'This photo can\'t be sent. Retake it or choose another.';

  @override
  String get noCardsFound =>
      'No cards found. Try a brighter, straighter photo.';

  @override
  String get dailyLimitReached =>
      'You\'ve reached today\'s limit for photos. Try again tomorrow.';

  @override
  String get modelFailed =>
      'Couldn\'t read the cards. Please try again in a moment.';

  @override
  String get signInRequired =>
      'You need to sign in. Sign in again from the account screen.';

  @override
  String get serviceFailed =>
      'Can\'t make cards from photos right now. Please try again in a moment.';

  @override
  String get photoUnreadable =>
      'Couldn\'t read this photo. Choose another one.';

  @override
  String get deckDeleted => 'This deck was deleted. Choose another deck.';

  @override
  String get browse => 'Browse';

  @override
  String get publish => 'Publish';

  @override
  String get unpublish => 'Make private';

  @override
  String get publishNeedsNetwork => 'Available when you\'re online';

  @override
  String get publicChip => 'Public';

  @override
  String get searchPublicDecks => 'Search names and descriptions';

  @override
  String get sortNewest => 'Newest';

  @override
  String get sortMostCopied => 'Most copied';

  @override
  String publicDeckLine(String owner, int cards, int copies) {
    String _temp0 = intl.Intl.pluralLogic(
      cards,
      locale: localeName,
      other: '$cards cards',
      one: '1 card',
    );
    String _temp1 = intl.Intl.pluralLogic(
      copies,
      locale: localeName,
      other: 'copied $copies times',
      one: 'copied once',
    );
    return '$owner · $_temp0 · $_temp1';
  }

  @override
  String get noPublicDecks =>
      'No public decks yet. Publish one of yours to be the first.';

  @override
  String get noPublicMatches => 'No decks match. Try other words.';

  @override
  String get browseOffline =>
      'You\'re offline. Public decks appear once you\'re connected.';

  @override
  String get loading => 'Loading';

  @override
  String get sharingOffline =>
      'You\'re offline. Check your connection and try again.';

  @override
  String get sharingRejected =>
      'The request was refused. Sign in again from the account screen and try again.';

  @override
  String get sharingFailed =>
      'Can\'t do that right now. Please try again in a moment.';

  @override
  String get deckNoLongerPublic => 'This deck is no longer public.';

  @override
  String get importToMyDecks => 'Add to my decks';

  @override
  String previewFirstCards(int shown, int total) {
    return 'First $shown of $total cards';
  }

  @override
  String get reportDeck => 'Report';

  @override
  String get blockUser => 'Block this user';

  @override
  String get reportTitle => 'Why are you reporting this deck?';

  @override
  String get reportInappropriate => 'Inappropriate content';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportCopyright => 'Copyright infringement';

  @override
  String get reportOther => 'Other';

  @override
  String get reported => 'Reported. We\'ll review it.';

  @override
  String get alreadyReported => 'You\'ve already reported this deck.';

  @override
  String blockTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get blockBody => 'Their decks will no longer appear when you browse.';

  @override
  String get block => 'Block';

  @override
  String blocked(String name) {
    return 'Blocked $name.';
  }

  @override
  String get importAsNewDeck => 'As a new deck';

  @override
  String get importIntoExistingDeck => 'Into a deck';

  @override
  String importNewDeckHint(String name) {
    return 'Creates the deck \"$name\" with every card.';
  }

  @override
  String get importTargetDeck => 'Deck';

  @override
  String get importDuplicates => 'Cards already in the deck';

  @override
  String get importConfirm => 'Add';

  @override
  String copiedCards(String deck, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count cards to \"$deck\"',
      one: 'Added 1 card to \"$deck\"',
      zero: 'No new cards for \"$deck\"',
    );
    return '$_temp0';
  }

  @override
  String publishTitle(String name) {
    return 'Publish \"$name\"';
  }

  @override
  String get displayName => 'Public name';

  @override
  String get displayNameHelp =>
      'Shown with your public decks. Your email is never shown.';

  @override
  String get displayNameLength => 'Use 2 to 20 characters';

  @override
  String get deckDescription => 'Description (optional)';

  @override
  String deckDescriptionTooLong(int max) {
    return 'Use at most $max characters';
  }

  @override
  String get publishAgreement =>
      'I won\'t publish inappropriate or copyrighted content';

  @override
  String get publishConfirm => 'Publish';

  @override
  String get published => 'Deck published';

  @override
  String get unpublished => 'Deck is private again';

  @override
  String get todayTitle => 'Today\'s cards';

  @override
  String get todayCountUnit => 'cards';

  @override
  String get emptyHomeTitle => 'Shall we make your first deck?';

  @override
  String get emptyHomeBody =>
      'Take a photo of a vocabulary page and we\'ll make the cards for you. You can also type them in.';

  @override
  String get createManually => 'Create by hand';

  @override
  String get browsePublicDecks => 'Browse public decks';

  @override
  String get newDeckTitle => 'Create a deck';

  @override
  String get newDeckBody => 'You can change the name later.';

  @override
  String statCards(int count) {
    return '$count cards';
  }

  @override
  String statReview(int count) {
    return '$count to review';
  }

  @override
  String statNew(int count) {
    return '$count new';
  }

  @override
  String get swipeDontKnowHint => 'Don\'t know';

  @override
  String get swipeKnowHint => 'Know';

  @override
  String get nextReviewToday =>
      'Your next review is today. We\'ll show these again just before you forget.';

  @override
  String get nextReviewTomorrow =>
      'Your next review is tomorrow. We\'ll show these again just before you forget.';

  @override
  String nextReviewInDays(int days) {
    return 'Your next review is in $days days. We\'ll show these again just before you forget.';
  }

  @override
  String get summaryStudied => 'Studied';

  @override
  String get timeSpentLabel => 'Time spent';

  @override
  String timeSpentValue(int minutes, int seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String get backToDecks => 'Back to decks';

  @override
  String consentNotice(String terms, String privacy) {
    return 'By continuing, you agree to the $terms and the $privacy.';
  }

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get linkNotOpened => 'Couldn\'t open the link. Please try again.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get todayDone => 'You\'ve done today\'s cards';
}
