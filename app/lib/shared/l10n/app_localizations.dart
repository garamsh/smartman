import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ko'),
    Locale('en'),
  ];

  /// The app's name, shown by the operating system.
  ///
  /// In ko, this message translates to:
  /// **'smartman'**
  String get appTitle;

  /// Title of the deck list screen.
  ///
  /// In ko, this message translates to:
  /// **'덱'**
  String get decksTitle;

  /// Shown when there is no deck.
  ///
  /// In ko, this message translates to:
  /// **'아직 덱이 없습니다'**
  String get noDecks;

  /// Button and dialog title for creating a deck.
  ///
  /// In ko, this message translates to:
  /// **'새 덱'**
  String get newDeck;

  /// Label of the menu button on a deck.
  ///
  /// In ko, this message translates to:
  /// **'덱 작업'**
  String get deckActions;

  /// Menu item and dialog title for renaming a deck.
  ///
  /// In ko, this message translates to:
  /// **'덱 이름 바꾸기'**
  String get renameDeck;

  /// Menu item for deleting a deck.
  ///
  /// In ko, this message translates to:
  /// **'덱 삭제'**
  String get deleteDeck;

  /// Title of the deck deletion confirmation.
  ///
  /// In ko, this message translates to:
  /// **'\"{name}\" 덱을 삭제할까요?'**
  String deleteDeckTitle(String name);

  /// Body of the deck deletion confirmation, naming how many cards go with the deck.
  ///
  /// In ko, this message translates to:
  /// **'{count, plural, =0{이 덱에는 카드가 없습니다.} other{카드 {count}장도 함께 삭제됩니다.}}'**
  String deleteDeckBody(int count);

  /// Label of the deck name field.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get deckName;

  /// Error shown when a deck name is empty.
  ///
  /// In ko, this message translates to:
  /// **'이름을 입력하세요'**
  String get deckNameRequired;

  /// Shown when a deck has no card.
  ///
  /// In ko, this message translates to:
  /// **'아직 카드가 없습니다'**
  String get noCards;

  /// Button and screen title for adding a card.
  ///
  /// In ko, this message translates to:
  /// **'새 카드'**
  String get newCard;

  /// Screen title for editing a card.
  ///
  /// In ko, this message translates to:
  /// **'카드 편집'**
  String get editCard;

  /// Button for deleting a card.
  ///
  /// In ko, this message translates to:
  /// **'카드 삭제'**
  String get deleteCard;

  /// Label of the card front field.
  ///
  /// In ko, this message translates to:
  /// **'앞면'**
  String get cardFront;

  /// Label of the card back field.
  ///
  /// In ko, this message translates to:
  /// **'뒷면'**
  String get cardBack;

  /// Error shown when a card side is empty.
  ///
  /// In ko, this message translates to:
  /// **'내용을 입력하세요'**
  String get cardSideRequired;

  /// Button for saving a card.
  ///
  /// In ko, this message translates to:
  /// **'카드 저장'**
  String get saveCard;

  /// Title of the dialog shown when a card's front duplicates another in the deck.
  ///
  /// In ko, this message translates to:
  /// **'같은 앞면의 카드가 있습니다'**
  String get duplicateTitle;

  /// Body of the duplicate dialog, quoting the existing card's front.
  ///
  /// In ko, this message translates to:
  /// **'이 덱에 앞면이 \"{front}\"인 카드가 이미 있습니다.'**
  String duplicateBody(String front);

  /// Duplicate dialog action that opens the existing card.
  ///
  /// In ko, this message translates to:
  /// **'기존 카드 열기'**
  String get openExistingCard;

  /// Duplicate dialog action that adds the new card anyway.
  ///
  /// In ko, this message translates to:
  /// **'그래도 추가'**
  String get addAnyway;

  /// Duplicate dialog action that saves the edited card anyway.
  ///
  /// In ko, this message translates to:
  /// **'그래도 저장'**
  String get saveAnyway;

  /// Stands in for a content block of a type this version cannot show.
  ///
  /// In ko, this message translates to:
  /// **'[이 버전에서 표시할 수 없는 내용: {type}]'**
  String unsupportedContent(String type);

  /// Shown when the local database fails.
  ///
  /// In ko, this message translates to:
  /// **'기기 저장소를 읽거나 쓰지 못했습니다. 다시 시도해 주세요.'**
  String get storageFailure;

  /// Shown when a stored card cannot be read.
  ///
  /// In ko, this message translates to:
  /// **'이 덱에 읽을 수 없는 카드가 있습니다.'**
  String get unreadableCard;

  /// Dismisses a dialog without acting.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancel;

  /// Confirms a dialog.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get save;

  /// Deck menu item for renaming.
  ///
  /// In ko, this message translates to:
  /// **'이름 바꾸기'**
  String get rename;

  /// Confirms a deletion.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get delete;

  /// Button on a deck that starts a study session.
  ///
  /// In ko, this message translates to:
  /// **'학습'**
  String get study;

  /// Answer button: the user knew the card.
  ///
  /// In ko, this message translates to:
  /// **'알아요'**
  String get know;

  /// Answer button: the user did not know the card.
  ///
  /// In ko, this message translates to:
  /// **'몰라요'**
  String get dontKnow;

  /// Heading of the panel showing the card answered just before.
  ///
  /// In ko, this message translates to:
  /// **'이전 카드'**
  String get previousCard;

  /// Hint on the previous-card panel: tapping it changes a Know answer to Don't know.
  ///
  /// In ko, this message translates to:
  /// **'탭하면 \'몰라요\'로 고칩니다'**
  String get correctToDontKnow;

  /// Accessibility label of the previous-card panel.
  ///
  /// In ko, this message translates to:
  /// **'이전 카드. 앞면: {front}. 뒷면: {back}. 답: {answer}'**
  String previousCardSemantics(String front, String back, String answer);

  /// Heading of the end-of-session summary.
  ///
  /// In ko, this message translates to:
  /// **'학습 끝'**
  String get sessionSummaryTitle;

  /// Shown in the summary when the deck had nothing due and no new card.
  ///
  /// In ko, this message translates to:
  /// **'지금 학습할 카드가 없습니다.'**
  String get nothingToStudy;

  /// Summary line: distinct cards answered in the session.
  ///
  /// In ko, this message translates to:
  /// **'학습한 카드: {count}장'**
  String cardsStudied(int count);

  /// Summary line: how many times Know was answered.
  ///
  /// In ko, this message translates to:
  /// **'알아요: {count}번'**
  String knowCount(int count);

  /// Summary line: how many times Don't know was answered.
  ///
  /// In ko, this message translates to:
  /// **'몰라요: {count}번'**
  String dontKnowCount(int count);

  /// Summary line: time from the first card to the end of the session.
  ///
  /// In ko, this message translates to:
  /// **'걸린 시간: {minutes}분 {seconds}초'**
  String timeSpent(int minutes, int seconds);

  /// Closes the session summary.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get done;

  /// Shown when an answer could not be written to the local database.
  ///
  /// In ko, this message translates to:
  /// **'답을 기기에 저장하지 못했습니다. 이 카드의 일정은 바뀌지 않았습니다.'**
  String get answerNotSaved;

  /// Shown when the scheduling engine refused a review.
  ///
  /// In ko, this message translates to:
  /// **'이 카드의 다음 복습 일정을 계산하지 못했습니다. 일정은 바뀌지 않았습니다.'**
  String get schedulingFailure;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
