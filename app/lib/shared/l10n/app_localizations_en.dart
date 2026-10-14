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
  String get noDecks => 'No decks yet';

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
  String get noCards => 'No cards yet';

  @override
  String get newCard => 'New card';

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
  String get saveCard => 'Save card';

  @override
  String get duplicateTitle => 'Duplicate front';

  @override
  String duplicateBody(String front) {
    return 'This deck already has a card with the front \"$front\".';
  }

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
}
