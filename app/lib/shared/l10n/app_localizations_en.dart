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
  String get decksTitle => 'Decks';

  @override
  String get noDecks => 'No decks yet. Create a new deck to start.';

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
  String get deckName => 'Name';

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
    return '$answered / $total';
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
  String get sessionSummaryTitle => 'Session complete';

  @override
  String get nothingToStudy => 'Nothing to study right now.';

  @override
  String cardsStudied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards studied',
      one: '1 card studied',
    );
    return '$_temp0';
  }

  @override
  String knowCount(int count) {
    return 'Know: $count';
  }

  @override
  String dontKnowCount(int count) {
    return 'Don\'t know: $count';
  }

  @override
  String timeSpent(int minutes, int seconds) {
    return 'Time spent: $minutes min $seconds s';
  }

  @override
  String get done => 'Done';

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
  String get signedOutBody => 'Everything works without an account.';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signingIn => 'Signing in';

  @override
  String signedInAs(String email) {
    return 'Signed in as $email';
  }

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
  String get displaySection => 'Display';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String todayBreakdown(int review, int fresh) {
    return 'Review $review · New $fresh';
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
  String deckSummary(int cards, int review, int fresh) {
    String _temp0 = intl.Intl.pluralLogic(
      cards,
      locale: localeName,
      other: '$cards cards',
      one: '1 card',
    );
    return '$_temp0 · $review to review today · $fresh new';
  }

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
}
