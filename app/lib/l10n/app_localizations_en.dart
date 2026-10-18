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
  String get showWholeCard => 'show the whole card';

  @override
  String get changeToKnow => 'Change to Know';

  @override
  String get changeToDontKnow => 'Change to Don\'t know';

  @override
  String get changingToKnow => 'Change to Know';

  @override
  String get changingToDontKnow => 'Change to Don\'t know';

  @override
  String guideSize(int cards, int minutes) {
    return 'Today $cards cards · about $minutes min';
  }

  @override
  String guideResume(int cards, int minutes) {
    return 'Picking up · $cards left · about $minutes min';
  }

  @override
  String get guideDone => 'You\'ve done today\'s cards';

  @override
  String get guideSwipe => 'Swipe right if you know it, left if you don\'t';

  @override
  String get guideRise =>
      'Answered cards come up here with their meaning. Swipe one to change it';

  @override
  String get answerNotSaved =>
      'Couldn\'t save your answer on this device. This card\'s schedule did not change.';

  @override
  String get studyComplete => 'Done for today';

  @override
  String get nothingToStudyToday => 'No cards to study today';

  @override
  String completionMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String completionStreak(int days) {
    return '$days d';
  }

  @override
  String completionSemantics(int know, int dontKnow, int minutes, int days) {
    return 'Know $know, don\'t know $dontKnow, $minutes min, $days-day streak';
  }

  @override
  String get studyOn => 'Study';

  @override
  String get noCardsLeft => 'No more cards to study';

  @override
  String get stopStudying => 'Stop';

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
  String myDecks(int count) {
    return 'My decks $count';
  }

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
  String get backlogPaused =>
      'New cards wait until you catch up on your reviews.';

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
  String photoTarget(String name) {
    return 'Add to · $name';
  }

  @override
  String get photoTargetTitle => 'Add to';

  @override
  String get photoSourceTitle => 'Add a photo';

  @override
  String get photoCamera => 'Take photo';

  @override
  String get photoAlbum => 'Choose from album';

  @override
  String get photoAccessDenied =>
      'The app isn\'t allowed to use the camera or your photos. Allow it in Settings.';

  @override
  String get cameraUnavailable =>
      'Couldn\'t open the camera. Choose a photo from your album.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get settingsNotOpened =>
      'Couldn\'t open Settings. Allow it in the Settings app.';

  @override
  String get photoThumbnail => 'Your photo';

  @override
  String get extractingTitle => 'Finding cards';

  @override
  String get extractingNote =>
      'Your photo is used only to make cards and isn\'t kept on the server';

  @override
  String choiceTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Made $count cards.',
      one: 'Made 1 card.',
    );
    return '$_temp0\nWhat will you memorise?';
  }

  @override
  String get choiceTopics => 'Topics to memorise';

  @override
  String get choiceTopicNone => 'This page';

  @override
  String choiceFrontLabel(String topic, String text) {
    return '$topic front: $text. Tap to change';
  }

  @override
  String choiceBackLabel(String topic, String text) {
    return '$topic back: $text. Tap to change';
  }

  @override
  String get choiceFrontName => 'Concept name';

  @override
  String get choiceFrontContent => 'Content first';

  @override
  String get choiceBackCore => 'Core only';

  @override
  String get choiceBackExamples => 'With examples';

  @override
  String get choiceNext => 'Next';

  @override
  String reviewMade(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Made $count cards',
      one: 'Made 1 card',
    );
    return '$_temp0';
  }

  @override
  String reviewTopic(String topic, int count) {
    return '$topic · $count';
  }

  @override
  String reviewTopicSwitch(String topic, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
    );
    return 'Keep $topic, $_temp0';
  }

  @override
  String reviewCard(String front, String back) {
    return '$front, $back. Tap to edit, swipe left to remove';
  }

  @override
  String reviewRemovedCard(String front, String back) {
    return '$front, $back. Removed. Swipe right to put it back';
  }

  @override
  String reviewDroppedCard(String front, String back) {
    return '$front, $back. Left out with its topic';
  }

  @override
  String get reviewRemove => 'Remove';

  @override
  String get reviewRestore => 'Put back';

  @override
  String get reviewRemoveCard => 'Remove this card';

  @override
  String get reviewDone => 'Done';

  @override
  String get reviewFront => 'Front';

  @override
  String get reviewBack => 'Back';

  @override
  String get reviewInDeck => 'Already in the deck';

  @override
  String reviewAdd(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count cards to the deck',
      one: 'Add 1 card to the deck',
    );
    return '$_temp0';
  }

  @override
  String get coachRemove => 'Swipe left to remove';

  @override
  String get coachRestore => 'Swipe right to put it back';

  @override
  String get coachEdit => 'Tap to edit';

  @override
  String coachStep(int step, int total) {
    return 'How to use, step $step of $total';
  }

  @override
  String get coachSkip => 'Skip';

  @override
  String get coachNext => 'Next';

  @override
  String get coachStart => 'Start';

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

  @override
  String get todayStudy => 'Study';

  @override
  String get tabToday => 'Today';

  @override
  String get tabDecks => 'Decks';

  @override
  String get tabRecord => 'Record';

  @override
  String get tabsLabel => 'Tabs';

  @override
  String get searchDecks => 'Search decks';

  @override
  String get noDeckMatches => 'No deck matches. Try other words.';

  @override
  String deckMastered(int cards, int mastered) {
    return '$mastered of $cards mastered';
  }

  @override
  String get browsePublicDecksBody => 'Copy decks other people made into yours';

  @override
  String get createManuallyBody => 'Name it and add cards one by one';

  @override
  String get createFromPhotoBody =>
      'Take a photo of a vocabulary page and we\'ll find the cards';

  @override
  String get importFromPublic => 'Copy a public deck';

  @override
  String get importFromPublicBody => 'Copy a deck someone else made';

  @override
  String progressSemantics(int mastered, int learning, int fresh) {
    return '$mastered mastered, $learning learning, $fresh new';
  }

  @override
  String deckSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
    );
    return '$_temp0';
  }

  @override
  String deckSummaryPublic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
    );
    return '$_temp0 · Public';
  }

  @override
  String get todayThisDeck => 'This deck today';

  @override
  String todayCountMinutes(int minutes) {
    return 'cards · about $minutes min';
  }

  @override
  String masteredOf(int mastered, int total) {
    return '$mastered / $total mastered';
  }

  @override
  String get studyDeck => 'Study';

  @override
  String get searchCardsAction => 'Search cards';

  @override
  String get closeSearch => 'Close search';

  @override
  String get addCardManually => 'Type it in';

  @override
  String get addCardManuallyBody => 'Write the question and the answer';

  @override
  String get addCardPhoto => 'Photo';

  @override
  String get addCardPhotoBody => 'Find cards in a photo of a vocabulary page';

  @override
  String cardListTitle(int count) {
    return 'Cards $count';
  }

  @override
  String get showMeanings => 'Show answers';

  @override
  String cardAnswerHidden(String front) {
    return '$front, answer hidden';
  }

  @override
  String cardAnswerShown(String front, String back) {
    return '$front, answer $back';
  }

  @override
  String goalRingSemantics(int done, int goal) {
    return '$done of today\'s goal of $goal';
  }

  @override
  String statusStreak(int days) {
    return 'On a $days-day streak';
  }

  @override
  String get statusWaiting => 'Waiting for today\'s first card';

  @override
  String get statusAlmostDone => 'Almost there';

  @override
  String get statusPastHalf => 'Past the halfway mark';

  @override
  String get statusStarted => 'Off to a good start';

  @override
  String goalReached(int goal) {
    return 'Goal of $goal reached';
  }

  @override
  String streakDays(int days) {
    return '$days-day streak';
  }

  @override
  String get forecastTitle => 'Next 7 days';

  @override
  String forecastSummary(int tomorrow, int week) {
    return 'Tomorrow $tomorrow · This week $week';
  }

  @override
  String forecastWeek(int week) {
    return 'This week $week';
  }

  @override
  String get forecastToday => 'Today';

  @override
  String get forecastTomorrow => 'Tomorrow';

  @override
  String forecastDay(String day, int count) {
    return '$day $count';
  }

  @override
  String get todayDecks => 'Today\'s decks';

  @override
  String deckDueCount(int count) {
    return '$count';
  }

  @override
  String studyDeckToday(String name, int count) {
    return 'Study $name, $count today';
  }

  @override
  String nextReview(String day, int cards, int minutes) {
    return 'Next review $day · $cards, about $minutes min';
  }

  @override
  String get noNextReview => 'No reviews in the next 7 days';

  @override
  String get backlogTitle => 'Pick up where you left off';

  @override
  String backlogBody(int count) {
    return '$count overdue reviews, most urgent first. New cards wait for now.';
  }

  @override
  String backlogStudy(int count, int minutes) {
    return 'Study $count · about $minutes min';
  }

  @override
  String catchUpTitle(int perDay, int days) {
    return 'At $perDay a day you catch up in $days days';
  }

  @override
  String catchUpNote(int perDay) {
    return 'The overdue reviews left at $perDay a day';
  }

  @override
  String catchUpSemantics(String days) {
    return 'Overdue reviews expected: $days';
  }

  @override
  String get statsPeriod => 'Period';

  @override
  String get statsPeriodWeek => '7 days';

  @override
  String get statsPeriodMonth => '30 days';

  @override
  String get statsPeriodAll => 'All';

  @override
  String get retentionTitle => 'Correct in reviews';

  @override
  String retentionPercent(int percent) {
    return '$percent%';
  }

  @override
  String get retentionTarget => 'Target';

  @override
  String retentionBelow(int points) {
    return '$points pt below target';
  }

  @override
  String retentionAbove(int points) {
    return '$points pt above target';
  }

  @override
  String get retentionOnTarget => 'On target';

  @override
  String retentionTargetLine(int percent) {
    return 'Target $percent%';
  }

  @override
  String retentionDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String get statsToday => 'Today';

  @override
  String get retentionEmpty => 'No reviews in this period.';

  @override
  String retentionSemantics(int target, String days) {
    return 'Correct in reviews, target $target%: $days';
  }

  @override
  String retentionDay(String date, int percent) {
    return '$date $percent%';
  }

  @override
  String get recallTitle => 'Chance you remember now';

  @override
  String recallMean(int percent) {
    return 'Average $percent%';
  }

  @override
  String get recallStrong => 'Solid';

  @override
  String get recallFair => 'Fair';

  @override
  String get recallFading => 'Fading soon';

  @override
  String statsCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
    );
    return '$_temp0';
  }

  @override
  String recallSemantics(
    int total,
    int strong,
    int fair,
    int fading,
    int mean,
  ) {
    return 'Of $total cards: solid $strong, fair $fair, fading soon $fading, average $mean%';
  }

  @override
  String get recallEmpty => 'No card reviewed yet.';

  @override
  String get masteredTitle => 'Mastered cards';

  @override
  String masteredGain(int count) {
    return '+$count in 4 weeks';
  }

  @override
  String masteredSemantics(String counts) {
    return 'Mastered cards by week, from 8 weeks ago to this week: $counts';
  }

  @override
  String get studyDaysTitle => 'Study days';

  @override
  String studyDaysStreak(int current, int best) {
    return '$current-day streak · best $best';
  }

  @override
  String studyDaysSemantics(int count, String days) {
    return 'Studied on $count days in the last 12 weeks: $days';
  }

  @override
  String get studyDaysNone => 'No study days in the last 12 weeks';

  @override
  String studyDay(String date, int count) {
    return '$date $count';
  }

  @override
  String get masteredEmpty => 'No card mastered yet.';

  @override
  String get newDeckEntryBody => 'Choose how to start a new deck';
}
