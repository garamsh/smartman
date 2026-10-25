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
  String get cardFront => 'Front';

  @override
  String get cardBack => 'Back';

  @override
  String get cardSideRequired => 'Enter some text';

  @override
  String get blank => 'blank';

  @override
  String get wholeCard => 'Card';

  @override
  String get sensesEditNote =>
      'Editing the front saves labels such as [명] as plain text.';

  @override
  String get cardKindBasic => 'Basic';

  @override
  String get cardKindWord => 'Word';

  @override
  String get cardKindCloze => 'Cloze';

  @override
  String get clozeWordsHint => 'Tap the words to make blanks';

  @override
  String clozeWord(String word) {
    return '$word';
  }

  @override
  String clozeWordBlank(String word) {
    return '$word, blank';
  }

  @override
  String get clozeBlankRequired => 'Choose at least one word as a blank';

  @override
  String get clozeBlankMarker =>
      '___ marks a blank, so the line can\'t contain it';

  @override
  String clozeBlankLine(int number, String answer) {
    return 'Blank $number: $answer';
  }

  @override
  String get clozePickLetters => 'Pick letters';

  @override
  String get clozeLettersTitle => 'Choose the letters to blank';

  @override
  String get clozeLettersBody => 'Tap the first letter, then the last';

  @override
  String get clozeLettersDone => 'Use these letters';

  @override
  String get cardKindTable => 'Table';

  @override
  String get tableNameHint => 'The table\'s name';

  @override
  String get tableModeLabel => 'Table editing';

  @override
  String get tableModeCells => 'Type cells';

  @override
  String get tableModeBlanks => 'Choose blanks';

  @override
  String get tableCellsHint => 'Type the headings and cells';

  @override
  String get tableBlanksHint => 'Tap the cells to make blanks';

  @override
  String tableHeaderCell(int column) {
    return 'Column $column heading';
  }

  @override
  String tableCell(int row, int column) {
    return 'Row $row, column $column';
  }

  @override
  String get tableEmptyCell => 'Empty';

  @override
  String get tableMakeBlank => 'Make blank';

  @override
  String get tableClearBlank => 'Remove blank';

  @override
  String get addRow => 'Add row';

  @override
  String get addColumn => 'Add column';

  @override
  String deleteRow(int row) {
    return 'Delete row $row';
  }

  @override
  String deleteColumn(int column) {
    return 'Delete column $column';
  }

  @override
  String get tableBlankRequired => 'Choose at least one cell as a blank';

  @override
  String get tableBlankEmpty => 'Fill in each cell chosen as a blank';

  @override
  String get cardKindLabel => 'Card kind';

  @override
  String senseHeading(int number) {
    return 'Meaning $number';
  }

  @override
  String get senseMeaning => 'Meaning';

  @override
  String get senseExamples => 'Examples';

  @override
  String get senseExamplesHint => 'One per line, or leave it empty';

  @override
  String get senseMeaningRequired => 'Enter the meaning';

  @override
  String get addSense => 'Add meaning';

  @override
  String moveSenseUp(int number) {
    return 'Move meaning $number up';
  }

  @override
  String moveSenseDown(int number) {
    return 'Move meaning $number down';
  }

  @override
  String deleteSense(int number) {
    return 'Delete meaning $number';
  }

  @override
  String get addLabel => 'Add label';

  @override
  String removeLabel(String label) {
    return 'Remove label [$label]';
  }

  @override
  String get labelSheetBody => 'Pick a part of speech or type another label.';

  @override
  String get otherLabel => 'Other label';

  @override
  String get otherLabelHint => 'e.g. object';

  @override
  String get addOtherLabel => 'Add this label';

  @override
  String partOfSpeechChoice(String short, String name) {
    return '[$short] $name';
  }

  @override
  String partOfSpeechName(String category) {
    String _temp0 = intl.Intl.selectLogic(category, {
      'noun': 'noun',
      'verb': 'verb',
      'adjective': 'adjective',
      'adverb': 'adverb',
      'pronoun': 'pronoun',
      'preposition': 'preposition',
      'conjunction': 'conjunction',
      'interjection': 'interjection',
      'determiner': 'determiner',
      'numeral': 'numeral',
      'particle': 'particle',
      'auxiliary': 'auxiliary',
      'classifier': 'classifier',
      'phrase': 'phrase',
      'other': '',
    });
    return '$_temp0';
  }

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
    return 'Responded to $answered of $total cards';
  }

  @override
  String currentCardSemantics(String front) {
    return 'Front: $front';
  }

  @override
  String get showBack => 'show the back';

  @override
  String get hideBack => 'hide the back';

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
    return 'Front: $front. Back: $back. Response: $answer$_temp0';
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
  String get previousPlaceholder => 'Cards you responded to stack up here';

  @override
  String get earlierCard => 'Last card last time';

  @override
  String resumeToast(int cards, int minutes) {
    return 'Picking up · $cards left · about $minutes min';
  }

  @override
  String get studyCoachKnow => 'Swipe right if you know it';

  @override
  String get studyCoachDontKnow => 'Swipe left if you don\'t';

  @override
  String get studyCoachRedecide =>
      'Cards you responded to come up here. Swipe one to change its response';

  @override
  String get studyCoachReplay => 'Show the guide again';

  @override
  String get studyCoachSampleFront => 'deadline';

  @override
  String get studyCoachSampleBack => 'the date by which it is due';

  @override
  String get answerNotSaved =>
      'Couldn\'t save your response on this device. This card\'s schedule did not change.';

  @override
  String get settingNotSaved =>
      'Couldn\'t save your study time on this device. Please try again.';

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
    return '$days-day streak';
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
      'Swipe to respond,\nand meet each card again just before you forget';

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
  String get photoTargetTitle => 'Add to';

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
  String readingTitle(int read, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'Read $read of $total photos',
      one: 'Read $read of 1 photo',
    );
    return '$_temp0';
  }

  @override
  String readingFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t read $count photos',
      one: 'Couldn\'t read 1 photo',
    );
    return '$_temp0';
  }

  @override
  String photosLeftToday(int count) {
    return 'You can read $count more today, so only the first $count will be read.';
  }

  @override
  String photoNumber(int number) {
    return 'Photo $number';
  }

  @override
  String get photoWaiting => 'Waiting';

  @override
  String get photoReading => 'Reading';

  @override
  String get photoDrop => 'Remove';

  @override
  String get addPhotos => 'Add more photos';

  @override
  String get discardImportTitle => 'Discard the cards found?';

  @override
  String discardImportBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $count cards found will be lost.',
      one: 'The 1 card found will be lost.',
    );
    return '$_temp0 Reading the photos again uses today\'s photo limit again.';
  }

  @override
  String get discardImport => 'Discard';

  @override
  String photoView(int number) {
    return 'View photo $number';
  }

  @override
  String photoViewerTitle(int current, int total) {
    return 'Photo $current of $total';
  }

  @override
  String get duplicateSkip => 'Skip';

  @override
  String get duplicateMergeBack => 'Merge back';

  @override
  String get duplicateAddNew => 'Add as new';

  @override
  String get retake => 'Retake';

  @override
  String get pickAnother => 'Pick another photo';

  @override
  String get makeDeck => 'Make a deck';

  @override
  String get photoCameraBody =>
      'Take a photo of a vocabulary page and we\'ll find the cards';

  @override
  String get photoAlbumBody => 'We\'ll find the cards in the photo you pick';

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
  String get accountSuspended =>
      'This account is suspended. Write to sauce@garam.sh with any questions.';

  @override
  String dailyLimitReachedOf(int limit) {
    return 'You\'ve used today\'s $limit photos. Try again tomorrow.';
  }

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
  String get browse => 'Public decks';

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
  String get copyToMyDecks => 'Add to my decks';

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
  String get copyAsNewDeck => 'As a new deck';

  @override
  String get copyIntoExistingDeck => 'Into a deck';

  @override
  String copyNewDeckHint(String name) {
    return 'Creates the deck \"$name\" with every card.';
  }

  @override
  String get copyTargetDeck => 'Deck';

  @override
  String get copyDuplicates => 'Cards already in the deck';

  @override
  String get copyConfirm => 'Add';

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
  String get noCardsTitle => 'Make your first card?';

  @override
  String get noCardsBody => 'Add cards to a deck to start';

  @override
  String get openDeck => 'Open deck';

  @override
  String get addCardsInDecks => 'Add cards in a deck';

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
  String get addCardManuallyBody => 'Write the front and the back';

  @override
  String cardListTitle(int count) {
    return 'Cards $count';
  }

  @override
  String get showMeanings => 'Show meanings';

  @override
  String cardBackHidden(String front) {
    return '$front, back hidden';
  }

  @override
  String cardBackShown(String front, String back) {
    return '$front, back $back';
  }

  @override
  String todayOfGoal(int goal) {
    return ' / $goal';
  }

  @override
  String todayAbout(int minutes) {
    return 'About $minutes min';
  }

  @override
  String todayAboutLeft(int minutes) {
    return 'About $minutes min left';
  }

  @override
  String todayProgress(int goal, int done) {
    return '$done of $goal cards';
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
  String get dayToday => 'Today';

  @override
  String get dayTomorrow => 'Tomorrow';

  @override
  String dayCount(String day, int count) {
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
    return 'Mastered cards by week, from 7 weeks ago to this week: $counts';
  }

  @override
  String get studyDaysTitle => 'Study days';

  @override
  String studyDaysStreak(int current, int best) {
    return '$current-day streak · best $best';
  }

  @override
  String masteredWeeksAgo(int weeks) {
    return '$weeks weeks ago';
  }

  @override
  String get masteredThisWeek => 'This week';

  @override
  String get studyDaysFewer => 'Fewer';

  @override
  String get studyDaysMore => 'More';

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

  @override
  String importTitleWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count words',
      one: 'Found 1 word',
    );
    return '$_temp0';
  }

  @override
  String importTitleCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Made $count cards',
      one: 'Made 1 card',
    );
    return '$_temp0';
  }

  @override
  String importDeck(String name) {
    return 'Adds to the deck \'$name\'';
  }

  @override
  String importAdd(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count cards',
      one: 'Add 1 card',
    );
    return '$_temp0';
  }

  @override
  String importSection(String topic, int count) {
    return '$topic $count';
  }

  @override
  String importIdentifySection(String topic) {
    return 'Identify · $topic';
  }

  @override
  String get importForward => 'Word → meaning';

  @override
  String get importBackward => 'Meaning → word';

  @override
  String get importBoth => 'Both ways';

  @override
  String get importBothShort => 'Both ways';

  @override
  String get importFirstSense => 'First meaning only';

  @override
  String get importShowPos => 'Show part of speech';

  @override
  String get importShowPronunciation => 'Show pronunciation';

  @override
  String get importShowExtras => 'Show synonyms and more';

  @override
  String get importNoteForward => 'Front → back';

  @override
  String get importNoteSwapped => 'Back → front';

  @override
  String get importSwap => 'Swap sides';

  @override
  String get importDropSection => 'Leave out this group';

  @override
  String get importKeepSection => 'Include this group';

  @override
  String importFormMenu(String topic, String form) {
    return '$topic card form, $form';
  }

  @override
  String importRow(String front, String back) {
    return '$front, $back. Tap to edit';
  }

  @override
  String importInclude(String front) {
    return 'Include $front';
  }

  @override
  String get importRemove => 'Remove';

  @override
  String get importInDeck => 'Already in the deck';

  @override
  String get editTitle => 'Edit card';

  @override
  String get editFront => 'Front';

  @override
  String get editBack => 'Back';

  @override
  String get editSenses => 'Meanings';

  @override
  String editSense(int number) {
    return 'Meaning $number';
  }

  @override
  String editKeepSense(int number) {
    return 'Include meaning $number';
  }

  @override
  String editMoveSense(int number) {
    return 'Move meaning $number';
  }

  @override
  String get editDone => 'Done';

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
  String get dailyMinutesTitle => 'Daily study time';

  @override
  String get dailyMinutesFirstTitle => 'How many minutes a day will you study?';

  @override
  String get dailyMinutesBody =>
      'Reviews come first, and new cards fill the time left.';

  @override
  String dailyMinutesChoice(int minutes) {
    return '$minutes min';
  }

  @override
  String get dailyMinutesLess => '5 minutes less';

  @override
  String get dailyMinutesMore => '5 minutes more';

  @override
  String get dailyMinutesNoTime =>
      'Reviews fill this time, so no new card starts';

  @override
  String get dailyMinutesAllStarted => 'You\'ve started every new card';

  @override
  String get dailyMinutesSkip => 'Skip';

  @override
  String get settingsStudy => 'Study';

  @override
  String studyExtra(int count) {
    return '+$count extra';
  }

  @override
  String studyExtraSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more cards studied past today\'s plan',
      one: '1 more card studied past today\'s plan',
    );
    return '$_temp0';
  }

  @override
  String todayExtra(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more cards today',
      one: '1 more card today',
    );
    return '$_temp0';
  }

  @override
  String get weekTitle => 'Last 7 days';

  @override
  String weekSummary(int cards, int minutes) {
    return 'This week $cards · $minutes min';
  }

  @override
  String weekSemantics(int cards, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      cards,
      locale: localeName,
      other: 'Studied $cards cards in $minutes min over the last 7 days',
      one: 'Studied 1 card in $minutes min over the last 7 days',
    );
    return '$_temp0';
  }

  @override
  String get weekOpenRecord => 'open Record';

  @override
  String get dailyMinutesUnit => 'min';

  @override
  String dailyMinutesNumberSemantics(int minutes) {
    return '$minutes minutes a day, tap to type';
  }

  @override
  String get dailyMinutesInput => 'Daily study time (minutes)';

  @override
  String get dailyMinutesOutOfRange => 'Enter 5 to 180 minutes';

  @override
  String get dailyMinutesFreshTitle => 'New cards a day';

  @override
  String dailyMinutesFreshValue(int count) {
    return 'About $count';
  }

  @override
  String get dailyMinutesAllTitle => 'All new cards started';

  @override
  String dailyMinutesAfterDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'In $days days',
      one: 'In 1 day',
    );
    return '$_temp0';
  }

  @override
  String get dailyMinutesAfterToday => 'Today';

  @override
  String get discardCardTitle => 'Discard this card?';

  @override
  String get discardCardBody => 'What you typed won\'t be saved.';

  @override
  String get discardCard => 'Discard';

  @override
  String get keepWriting => 'Keep writing';
}
