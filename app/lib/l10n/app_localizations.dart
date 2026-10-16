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
  /// **'{count, plural, =0{이 덱에는 카드가 없어요.} other{카드 {count}장도 함께 삭제돼요.}}'**
  String deleteDeckBody(int count);

  /// Label of the deck name field.
  ///
  /// In ko, this message translates to:
  /// **'덱 이름'**
  String get deckName;

  /// Error shown when a deck name is empty.
  ///
  /// In ko, this message translates to:
  /// **'이름을 입력하세요'**
  String get deckNameRequired;

  /// Shown when a deck has no card.
  ///
  /// In ko, this message translates to:
  /// **'아직 카드가 없어요. 카드를 추가해 시작해 보세요.'**
  String get noCards;

  /// Bottom-bar button and editor title for adding a card.
  ///
  /// In ko, this message translates to:
  /// **'카드 추가'**
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

  /// Label of the card front field: the question side.
  ///
  /// In ko, this message translates to:
  /// **'문제'**
  String get cardFront;

  /// Label of the card back field: the answer side.
  ///
  /// In ko, this message translates to:
  /// **'답'**
  String get cardBack;

  /// Error shown when a card side is empty.
  ///
  /// In ko, this message translates to:
  /// **'내용을 입력하세요'**
  String get cardSideRequired;

  /// Title of the sheet shown when a card's front duplicates another in the deck.
  ///
  /// In ko, this message translates to:
  /// **'이 덱에 이미 있는 카드예요'**
  String get duplicateTitle;

  /// Line under the duplicate sheet's title: comparing fronts ignores case and spacing.
  ///
  /// In ko, this message translates to:
  /// **'대소문자와 띄어쓰기는 구분하지 않아요.'**
  String get duplicateBody;

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
  /// **'기기 저장소를 읽거나 쓰지 못했어요. 다시 시도해 주세요.'**
  String get storageFailure;

  /// Shown when a stored card cannot be read.
  ///
  /// In ko, this message translates to:
  /// **'이 덱에 읽을 수 없는 카드가 있어요.'**
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

  /// Primary button of the sheet that names a new deck.
  ///
  /// In ko, this message translates to:
  /// **'만들기'**
  String get create;

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

  /// Label of the button that leaves the deck list's selection mode.
  ///
  /// In ko, this message translates to:
  /// **'선택 해제'**
  String get clearSelection;

  /// Deck list title in selection mode: how many decks are selected.
  ///
  /// In ko, this message translates to:
  /// **'{count}개 선택됨'**
  String decksSelected(int count);

  /// Deck list action in selection mode that studies the selected decks in one session, with how many are selected.
  ///
  /// In ko, this message translates to:
  /// **'학습 ({count})'**
  String studySelected(int count);

  /// Deck list header: how many cards a session over every deck would study now.
  ///
  /// In ko, this message translates to:
  /// **'오늘 할 카드 {count}장'**
  String todayCards(int count);

  /// Deck list header action that studies every deck in one session.
  ///
  /// In ko, this message translates to:
  /// **'모두 학습'**
  String get studyAll;

  /// Answer: the user knew the card. Shown on the current card while it is dragged right, and the name of its screen-reader action.
  ///
  /// In ko, this message translates to:
  /// **'안다'**
  String get know;

  /// Answer: the user did not know the card. Shown on the current card while it is dragged left, and the name of its screen-reader action.
  ///
  /// In ko, this message translates to:
  /// **'모른다'**
  String get dontKnow;

  /// Label of the study screen's close button.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get close;

  /// Study screen top bar: cards answered so far out of the cards in the session.
  ///
  /// In ko, this message translates to:
  /// **'{answered}/{total}'**
  String studyProgress(int answered, int total);

  /// Accessibility label of the study progress: cards answered out of the cards in the session.
  ///
  /// In ko, this message translates to:
  /// **'{total}장 중 {answered}장 답함'**
  String studyProgressSemantics(int answered, int total);

  /// Accessibility label of the current card while its answer is hidden.
  ///
  /// In ko, this message translates to:
  /// **'앞면: {front}'**
  String currentCardSemantics(String front);

  /// Accessibility label of the current card while its answer is shown.
  ///
  /// In ko, this message translates to:
  /// **'앞면: {front}. 뒷면: {back}'**
  String currentCardRevealedSemantics(String front, String back);

  /// Accessibility hint of tapping the current card while its answer is hidden.
  ///
  /// In ko, this message translates to:
  /// **'답 보기'**
  String get showAnswer;

  /// Accessibility hint of tapping the current card while its answer is shown.
  ///
  /// In ko, this message translates to:
  /// **'답 가리기'**
  String get hideAnswer;

  /// Accessibility label of a card answered earlier in the session; changed is 'yes' when the answer differs from the one first given.
  ///
  /// In ko, this message translates to:
  /// **'앞면: {front}. 뒷면: {back}. 답: {answer}{changed, select, yes{. 수정됨} other{}}'**
  String previousCardSemantics(
    String front,
    String back,
    String answer,
    String changed,
  );

  /// Accessibility hint of long-pressing a card answered earlier: it opens the whole card.
  ///
  /// In ko, this message translates to:
  /// **'카드 전체 보기'**
  String get showWholeCard;

  /// Screen-reader action on a card answered earlier as Don't know: changes its answer to Know.
  ///
  /// In ko, this message translates to:
  /// **'안다로 바꾸기'**
  String get changeToKnow;

  /// Screen-reader action on a card answered earlier as Know: changes its answer to Don't know.
  ///
  /// In ko, this message translates to:
  /// **'모른다로 바꾸기'**
  String get changeToDontKnow;

  /// Shown behind a card answered earlier while it is dragged right, toward Know.
  ///
  /// In ko, this message translates to:
  /// **'안다로 바꿔요'**
  String get changingToKnow;

  /// Shown behind a card answered earlier while it is dragged left, toward Don't know.
  ///
  /// In ko, this message translates to:
  /// **'모른다로 바꿔요'**
  String get changingToDontKnow;

  /// Button shown while the study screen is scrolled back to earlier cards: returns to the current card.
  ///
  /// In ko, this message translates to:
  /// **'지금 카드로'**
  String get backToCurrent;

  /// First study session's guide, first line: recall first, then tap the card to see the answer.
  ///
  /// In ko, this message translates to:
  /// **'먼저 떠올려 보고, 카드를 탭해 답을 확인해요'**
  String get guideReveal;

  /// First study session's guide, second line: swipe right when you know it, left when you don't.
  ///
  /// In ko, this message translates to:
  /// **'알면 오른쪽, 모르면 왼쪽으로 밀어요'**
  String get guideSwipe;

  /// First study session's guide, third line: pull down to see earlier cards and change their answers.
  ///
  /// In ko, this message translates to:
  /// **'아래로 내리면 지난 카드를 보고 답을 바꿀 수 있어요'**
  String get guideEarlier;

  /// Shown when an answer could not be written to the local database.
  ///
  /// In ko, this message translates to:
  /// **'답을 기기에 저장하지 못했어요. 이 카드의 일정은 그대로예요.'**
  String get answerNotSaved;

  /// Heading of the completion card, shown in the current card's place once no card is left today.
  ///
  /// In ko, this message translates to:
  /// **'오늘 학습 완료'**
  String get studyComplete;

  /// The study screen when no card is left today and none of its decks' cards was answered today.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 학습할 카드가 없어요'**
  String get nothingToStudyToday;

  /// The completion card's time on screen today, in whole minutes rounded up.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String completionMinutes(int minutes);

  /// The completion card's streak, after a flame icon: study days in a row.
  ///
  /// In ko, this message translates to:
  /// **'{days}일'**
  String completionStreak(int days);

  /// What a screen reader reads for the completion card's line of counts.
  ///
  /// In ko, this message translates to:
  /// **'안다 {know}, 모른다 {dontKnow}, {minutes}분, {days}일 연속'**
  String completionSemantics(int know, int dontKnow, int minutes, int days);

  /// The completion card's primary button: goes on as practice over the cards answered today.
  ///
  /// In ko, this message translates to:
  /// **'계속 학습'**
  String get keepStudying;

  /// The completion card's quiet button: closes the study screen.
  ///
  /// In ko, this message translates to:
  /// **'그만하기'**
  String get stopStudying;

  /// Shown when the scheduling engine refused a review.
  ///
  /// In ko, this message translates to:
  /// **'이 카드의 다음 복습 일정을 계산하지 못했어요. 일정은 그대로예요.'**
  String get schedulingFailure;

  /// Label of the home screen button that opens the account screen.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get account;

  /// Title of the account screen.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get accountTitle;

  /// Sign-in screen line under the logo, saying what the app does, in two lines.
  ///
  /// In ko, this message translates to:
  /// **'밀어서 답하고,\n잊을 때쯤 다시 만나는 암기 카드'**
  String get welcomeBody;

  /// Button that opens Google's account picker to sign in.
  ///
  /// In ko, this message translates to:
  /// **'Google로 계속하기'**
  String get signInWithGoogle;

  /// Disabled sign-in screen button holding the place of Apple sign-in, which is not available yet.
  ///
  /// In ko, this message translates to:
  /// **'Apple로 계속하기 · 준비 중'**
  String get signInWithAppleSoon;

  /// Accessible label of the progress indicator while signing in.
  ///
  /// In ko, this message translates to:
  /// **'로그인 중'**
  String get signingIn;

  /// Account screen text while signed in to an account without an email.
  ///
  /// In ko, this message translates to:
  /// **'로그인했어요'**
  String get signedIn;

  /// Button that signs out.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get signOut;

  /// Accessible label of the progress indicator while signing out.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃 중'**
  String get signingOut;

  /// Shown when signing in or out could not reach the server.
  ///
  /// In ko, this message translates to:
  /// **'서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.'**
  String get accountOffline;

  /// Shown when the app's sign-in configuration is missing or rejected by Google or Supabase.
  ///
  /// In ko, this message translates to:
  /// **'이 앱의 로그인 설정에 문제가 있어 로그인할 수 없어요.'**
  String get accountMisconfigured;

  /// Shown when Google or Supabase refused the sign-in.
  ///
  /// In ko, this message translates to:
  /// **'Google 로그인이 거부됐어요. 다시 시도해 주세요.'**
  String get accountRejected;

  /// Heading of the account screen section that holds sign-out.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get accountSection;

  /// Heading of the account screen section that chooses the theme.
  ///
  /// In ko, this message translates to:
  /// **'화면'**
  String get displaySection;

  /// Theme choice: follow the device light or dark setting.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get themeSystem;

  /// Theme choice: always light.
  ///
  /// In ko, this message translates to:
  /// **'라이트'**
  String get themeLight;

  /// Theme choice: always dark.
  ///
  /// In ko, this message translates to:
  /// **'다크'**
  String get themeDark;

  /// Today card line under the count: due reviews, new cards, and the minutes the session takes at the user's pace.
  ///
  /// In ko, this message translates to:
  /// **'복습 {review} · 새 카드 {fresh} · 약 {minutes}분'**
  String todayBreakdown(int review, int fresh, int minutes);

  /// Label above the deck rows, with how many decks there are.
  ///
  /// In ko, this message translates to:
  /// **'내 덱 {count}'**
  String myDecks(int count);

  /// Hint beside the deck rows label: a long-press selects several decks.
  ///
  /// In ko, this message translates to:
  /// **'길게 눌러 여러 덱 선택'**
  String get selectHint;

  /// How many cards a deck holds, under its name.
  ///
  /// In ko, this message translates to:
  /// **'카드 {count}장'**
  String cardCount(int count);

  /// Chip on a deck row: how many of its cards a session would study now.
  ///
  /// In ko, this message translates to:
  /// **'오늘 {count}'**
  String todayChip(int count);

  /// Deck list bottom-bar button that creates a deck from a photo.
  ///
  /// In ko, this message translates to:
  /// **'사진으로 만들기'**
  String get createFromPhoto;

  /// Card list bottom-bar button that adds cards from a photo.
  ///
  /// In ko, this message translates to:
  /// **'사진으로 추가'**
  String get addFromPhoto;

  /// Sentence under the today count while so many reviews are due that a session takes no new card.
  ///
  /// In ko, this message translates to:
  /// **'밀린 복습을 마칠 때까지 새 카드는 쉬어요.'**
  String get backlogPaused;

  /// Deck screen button that studies the deck, with how many cards the session would study.
  ///
  /// In ko, this message translates to:
  /// **'학습하기 · {count}장'**
  String studyCount(int count);

  /// Hint of the card list search field.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get searchCards;

  /// Shown when no card matches the card list search.
  ///
  /// In ko, this message translates to:
  /// **'찾는 카드가 없어요. 다른 단어로 검색해 보세요.'**
  String get noMatches;

  /// Editor button that saves the card and opens an empty editor for the next one.
  ///
  /// In ko, this message translates to:
  /// **'저장하고 다음 카드'**
  String get saveAndNext;

  /// Title of the card deletion confirmation.
  ///
  /// In ko, this message translates to:
  /// **'이 카드를 삭제할까요?'**
  String get deleteCardTitle;

  /// Body of the card deletion confirmation: the card review history goes with it.
  ///
  /// In ko, this message translates to:
  /// **'이 카드의 학습 기록도 함께 삭제돼요.'**
  String get deleteCardBody;

  /// Title of the sign-out warning shown when some changes could not reach the server.
  ///
  /// In ko, this message translates to:
  /// **'동기화되지 않은 변경이 있어요'**
  String get unsyncedChangesTitle;

  /// Body of the sign-out warning: unsynced changes are lost when signing out.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃하면 이 기기에서 지워지고 다른 기기에서는 볼 수 없어요.'**
  String get unsyncedChangesBody;

  /// Sign-out warning action that signs out despite unsynced changes.
  ///
  /// In ko, this message translates to:
  /// **'그래도 로그아웃'**
  String get signOutAnyway;

  /// Shown when sign-out could not clear the device's data.
  ///
  /// In ko, this message translates to:
  /// **'이 기기의 데이터를 지우지 못했어요. 다른 계정으로 로그인하면 지워져요.'**
  String get dataNotCleared;

  /// Account screen row that deletes the account.
  ///
  /// In ko, this message translates to:
  /// **'계정 삭제'**
  String get deleteAccount;

  /// Line under the delete-account row: what deletion removes, and that it cannot be undone.
  ///
  /// In ko, this message translates to:
  /// **'계정을 삭제하면 서버와 이 기기에 있는 카드와 기록이 모두 지워져요. 되돌릴 수 없어요.'**
  String get deleteAccountNote;

  /// Title of the account deletion confirmation.
  ///
  /// In ko, this message translates to:
  /// **'계정을 삭제할까요?'**
  String get deleteAccountTitle;

  /// Body of the account deletion confirmation: what is removed, and what stays.
  ///
  /// In ko, this message translates to:
  /// **'서버와 이 기기의 덱, 카드, 학습 기록이 모두 지워지고, 다른 사람이 복사한 덱과 Google 계정은 남아요.'**
  String get deleteAccountBody;

  /// Accessible label of the progress indicator while deleting the account.
  ///
  /// In ko, this message translates to:
  /// **'계정 삭제 중'**
  String get deletingAccount;

  /// Shown when the server refused to delete the account.
  ///
  /// In ko, this message translates to:
  /// **'계정을 삭제하지 못했어요. 다시 시도해 주세요.'**
  String get deleteAccountRejected;

  /// Account screen sync status while a sync runs.
  ///
  /// In ko, this message translates to:
  /// **'동기화 중'**
  String get syncSyncing;

  /// Account screen sync status after a sync finished.
  ///
  /// In ko, this message translates to:
  /// **'동기화됨'**
  String get syncSynced;

  /// Account screen sync status when the server could not be reached; sync retries by itself.
  ///
  /// In ko, this message translates to:
  /// **'오프라인 · 연결되면 동기화해요'**
  String get syncOffline;

  /// Account screen sync status when a sync failed.
  ///
  /// In ko, this message translates to:
  /// **'동기화하지 못했어요'**
  String get syncFailed;

  /// Button that runs sync again after a failure.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get syncRetry;

  /// Hint over the camera view of photo import.
  ///
  /// In ko, this message translates to:
  /// **'단어장이나 책 한 페이지를 틀 안에 맞춰 찍어 주세요'**
  String get photoCaptureHint;

  /// Chip on the camera view naming the deck the cards go into; tapping it switches the deck.
  ///
  /// In ko, this message translates to:
  /// **'추가할 덱 · {name}'**
  String photoTarget(String name);

  /// Title of the sheet on the camera view that chooses the deck the cards go into.
  ///
  /// In ko, this message translates to:
  /// **'추가할 덱'**
  String get photoTargetTitle;

  /// Tooltip of the camera view's album button.
  ///
  /// In ko, this message translates to:
  /// **'앨범에서 고르기'**
  String get photoAlbum;

  /// Tooltip of the camera view's shutter button.
  ///
  /// In ko, this message translates to:
  /// **'사진 찍기'**
  String get photoShutter;

  /// Shown in place of the camera preview when camera access is refused.
  ///
  /// In ko, this message translates to:
  /// **'카메라 사용이 허용되지 않았어요. 설정에서 허용하거나 앨범에서 사진을 골라 주세요.'**
  String get cameraDenied;

  /// Shown in place of the camera preview when the device has no usable camera.
  ///
  /// In ko, this message translates to:
  /// **'카메라를 열 수 없어요. 앨범에서 사진을 골라 주세요.'**
  String get cameraUnavailable;

  /// Semantic label of the photo thumbnail while cards are extracted.
  ///
  /// In ko, this message translates to:
  /// **'찍은 사진'**
  String get photoThumbnail;

  /// Title while the photo is sent for extraction.
  ///
  /// In ko, this message translates to:
  /// **'카드를 찾고 있어요'**
  String get extractingTitle;

  /// Privacy note shown while cards are extracted.
  ///
  /// In ko, this message translates to:
  /// **'사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요'**
  String get extractingNote;

  /// Title of the review screen: how many candidate cards were found.
  ///
  /// In ko, this message translates to:
  /// **'카드 {count}개를 찾았어요'**
  String reviewTitle(int count);

  /// Line under the review title, ending with the deck the cards go into.
  ///
  /// In ko, this message translates to:
  /// **'눌러서 고치고, 뺄 카드는 체크를 끄세요 · {deck}'**
  String reviewHint(String deck);

  /// Label of the selector of how much each photo card's answer says, on the capture and review screens.
  ///
  /// In ko, this message translates to:
  /// **'카드에 담을 내용'**
  String get detailLevelLabel;

  /// Detail level: the meaning alone.
  ///
  /// In ko, this message translates to:
  /// **'간단'**
  String get detailLevelSimple;

  /// Detail level, the default: the part of speech the page prints, then the meaning.
  ///
  /// In ko, this message translates to:
  /// **'기본'**
  String get detailLevelBasic;

  /// Detail level: the basic answer, then each example the page prints on its own line.
  ///
  /// In ko, this message translates to:
  /// **'자세히'**
  String get detailLevelDetailed;

  /// Mark on a candidate whose answer the user edited, which a detail level switch leaves as typed.
  ///
  /// In ko, this message translates to:
  /// **'직접 고침'**
  String get candidateEdited;

  /// Heading of the candidates whose card key matches a card in the deck.
  ///
  /// In ko, this message translates to:
  /// **'이미 있는 카드 {count}개'**
  String reviewDuplicates(int count);

  /// Semantic label of a candidate's checkbox.
  ///
  /// In ko, this message translates to:
  /// **'포함'**
  String get includeCard;

  /// Duplicate option: write nothing for this candidate.
  ///
  /// In ko, this message translates to:
  /// **'건너뛰기'**
  String get duplicateSkip;

  /// Duplicate option: append this back to the existing card's back.
  ///
  /// In ko, this message translates to:
  /// **'뒷면 합치기'**
  String get duplicateMergeBack;

  /// Duplicate option: add this candidate as a separate card.
  ///
  /// In ko, this message translates to:
  /// **'새 카드로 추가'**
  String get duplicateAddNew;

  /// Button that returns to the camera for a new photo.
  ///
  /// In ko, this message translates to:
  /// **'다시 찍기'**
  String get retake;

  /// Button that sends the same photo again.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get retry;

  /// Primary button of the review screen, with how many cards it adds or merges.
  ///
  /// In ko, this message translates to:
  /// **'카드 {count}개 추가'**
  String addCards(int count);

  /// Photo import failure: the server could not be reached.
  ///
  /// In ko, this message translates to:
  /// **'인터넷에 연결되지 않았어요. 연결을 확인하고 다시 시도해 주세요.'**
  String get extractionOffline;

  /// Photo import failure: the photo was too large or of an unsupported type.
  ///
  /// In ko, this message translates to:
  /// **'이 사진은 보낼 수 없어요. 다시 찍거나 다른 사진을 골라 주세요.'**
  String get photoRefused;

  /// Photo import failure: the model found no card on the page.
  ///
  /// In ko, this message translates to:
  /// **'카드를 찾지 못했어요. 더 밝고 반듯하게 찍어 보세요.'**
  String get noCardsFound;

  /// Photo import failure: the daily extraction limit was reached.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 사진으로 카드를 더 만들 수 없어요. 내일 다시 시도해 주세요.'**
  String get dailyLimitReached;

  /// Photo import failure: the model failed.
  ///
  /// In ko, this message translates to:
  /// **'카드를 읽지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get modelFailed;

  /// Photo import failure: no session, or one the server refused.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 필요해요. 계정 화면에서 다시 로그인해 주세요.'**
  String get signInRequired;

  /// Photo import failure: the server answered unexpectedly.
  ///
  /// In ko, this message translates to:
  /// **'지금은 사진으로 카드를 만들 수 없어요. 잠시 후 다시 시도해 주세요.'**
  String get serviceFailed;

  /// Photo import failure: the file is not an image the app reads.
  ///
  /// In ko, this message translates to:
  /// **'이 사진을 읽을 수 없어요. 다른 사진을 골라 주세요.'**
  String get photoUnreadable;

  /// Shown when cards are saved into a deck that was deleted meanwhile, such as on another device.
  ///
  /// In ko, this message translates to:
  /// **'이 덱은 삭제됐어요. 다른 덱을 골라 주세요.'**
  String get deckDeleted;

  /// Opens other users' public decks; also the title of that screen.
  ///
  /// In ko, this message translates to:
  /// **'둘러보기'**
  String get browse;

  /// Deck menu item that publishes the deck.
  ///
  /// In ko, this message translates to:
  /// **'공개하기'**
  String get publish;

  /// Deck menu item that makes a public deck private.
  ///
  /// In ko, this message translates to:
  /// **'비공개로 전환'**
  String get unpublish;

  /// Why publishing is disabled: the device is offline.
  ///
  /// In ko, this message translates to:
  /// **'인터넷에 연결되면 바꿀 수 있어요'**
  String get publishNeedsNetwork;

  /// Chip beside a deck the user has published.
  ///
  /// In ko, this message translates to:
  /// **'공개'**
  String get publicChip;

  /// Hint of the search field on the browse screen.
  ///
  /// In ko, this message translates to:
  /// **'덱 이름이나 설명으로 검색'**
  String get searchPublicDecks;

  /// Browse sort: most recently published first.
  ///
  /// In ko, this message translates to:
  /// **'최신순'**
  String get sortNewest;

  /// Browse sort: most copied first.
  ///
  /// In ko, this message translates to:
  /// **'가져오기 많은 순'**
  String get sortMostCopied;

  /// A public deck's owner display name, card count and copy count.
  ///
  /// In ko, this message translates to:
  /// **'{owner} · 카드 {cards}장 · 가져오기 {copies}회'**
  String publicDeckLine(String owner, int cards, int copies);

  /// Browse screen with no public deck.
  ///
  /// In ko, this message translates to:
  /// **'아직 공개된 덱이 없어요. 내 덱을 공개해 처음으로 나눠 보세요.'**
  String get noPublicDecks;

  /// Browse search with no match.
  ///
  /// In ko, this message translates to:
  /// **'찾는 덱이 없어요. 다른 단어로 검색해 보세요.'**
  String get noPublicMatches;

  /// Browse screen while offline.
  ///
  /// In ko, this message translates to:
  /// **'인터넷에 연결되지 않았어요. 연결되면 공개 덱을 볼 수 있어요.'**
  String get browseOffline;

  /// Label of a progress indicator.
  ///
  /// In ko, this message translates to:
  /// **'불러오는 중'**
  String get loading;

  /// Sharing failure: the server could not be reached.
  ///
  /// In ko, this message translates to:
  /// **'인터넷에 연결되지 않았어요. 연결을 확인하고 다시 시도해 주세요.'**
  String get sharingOffline;

  /// Sharing failure: the server refused the session or the request.
  ///
  /// In ko, this message translates to:
  /// **'요청이 거절됐어요. 계정 화면에서 다시 로그인한 뒤 시도해 주세요.'**
  String get sharingRejected;

  /// Sharing failure: the server answered unexpectedly.
  ///
  /// In ko, this message translates to:
  /// **'지금은 처리할 수 없어요. 잠시 후 다시 시도해 주세요.'**
  String get sharingFailed;

  /// Copying a deck its owner made private, deleted, or that was hidden.
  ///
  /// In ko, this message translates to:
  /// **'이 덱은 더 이상 공개되어 있지 않아요.'**
  String get deckNoLongerPublic;

  /// Primary button of a public deck, and title of the sheet it opens.
  ///
  /// In ko, this message translates to:
  /// **'내 덱으로 가져오기'**
  String get importToMyDecks;

  /// Below a public deck's preview when it holds more cards than shown.
  ///
  /// In ko, this message translates to:
  /// **'카드 {total}장 중 처음 {shown}장'**
  String previewFirstCards(int shown, int total);

  /// Menu item and dialog button that report a public deck.
  ///
  /// In ko, this message translates to:
  /// **'신고하기'**
  String get reportDeck;

  /// Menu item that blocks a public deck's owner.
  ///
  /// In ko, this message translates to:
  /// **'이 사용자 차단'**
  String get blockUser;

  /// Title of the report dialog.
  ///
  /// In ko, this message translates to:
  /// **'신고 이유'**
  String get reportTitle;

  /// Report reason.
  ///
  /// In ko, this message translates to:
  /// **'부적절한 내용'**
  String get reportInappropriate;

  /// Report reason.
  ///
  /// In ko, this message translates to:
  /// **'스팸'**
  String get reportSpam;

  /// Report reason.
  ///
  /// In ko, this message translates to:
  /// **'저작권 침해'**
  String get reportCopyright;

  /// Report reason.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get reportOther;

  /// After a report was filed.
  ///
  /// In ko, this message translates to:
  /// **'신고했어요. 검토할게요.'**
  String get reported;

  /// After a second report of the same deck.
  ///
  /// In ko, this message translates to:
  /// **'이미 신고한 덱이에요.'**
  String get alreadyReported;

  /// Title of the block confirmation.
  ///
  /// In ko, this message translates to:
  /// **'{name} 님을 차단할까요?'**
  String blockTitle(String name);

  /// Body of the block confirmation.
  ///
  /// In ko, this message translates to:
  /// **'이 사용자의 덱이 둘러보기에 더 이상 나오지 않아요.'**
  String get blockBody;

  /// Confirms blocking a user.
  ///
  /// In ko, this message translates to:
  /// **'차단'**
  String get block;

  /// After a user was blocked.
  ///
  /// In ko, this message translates to:
  /// **'{name} 님을 차단했어요.'**
  String blocked(String name);

  /// Import option: copy into a new deck.
  ///
  /// In ko, this message translates to:
  /// **'새 덱으로'**
  String get importAsNewDeck;

  /// Import option: copy into one of the user's decks.
  ///
  /// In ko, this message translates to:
  /// **'기존 덱에 추가'**
  String get importIntoExistingDeck;

  /// What importing as a new deck does.
  ///
  /// In ko, this message translates to:
  /// **'\"{name}\" 덱을 새로 만들어 모든 카드를 가져와요.'**
  String importNewDeckHint(String name);

  /// Label of the deck chooser when importing into a deck.
  ///
  /// In ko, this message translates to:
  /// **'덱'**
  String get importTargetDeck;

  /// Heading of the duplicate options when importing into a deck.
  ///
  /// In ko, this message translates to:
  /// **'이미 있는 카드는'**
  String get importDuplicates;

  /// Button that copies a public deck.
  ///
  /// In ko, this message translates to:
  /// **'가져오기'**
  String get importConfirm;

  /// After copying a public deck: how many cards were added or merged, and into which deck.
  ///
  /// In ko, this message translates to:
  /// **'{count, plural, =0{\"{deck}\"에 새로 가져온 카드가 없어요} other{\"{deck}\"에 카드 {count}장을 가져왔어요}}'**
  String copiedCards(String deck, int count);

  /// Title of the publish sheet.
  ///
  /// In ko, this message translates to:
  /// **'\"{name}\" 공개하기'**
  String publishTitle(String name);

  /// Label of the display name field.
  ///
  /// In ko, this message translates to:
  /// **'공개 이름'**
  String get displayName;

  /// Help below the display name field.
  ///
  /// In ko, this message translates to:
  /// **'공개한 덱에 이 이름이 표시돼요. 이메일은 표시되지 않아요.'**
  String get displayNameHelp;

  /// Error for a display name of the wrong length.
  ///
  /// In ko, this message translates to:
  /// **'2~20자로 입력하세요'**
  String get displayNameLength;

  /// Label of the description field when publishing.
  ///
  /// In ko, this message translates to:
  /// **'설명 (선택)'**
  String get deckDescription;

  /// Error for a description that is too long.
  ///
  /// In ko, this message translates to:
  /// **'{max}자 이내로 입력하세요'**
  String deckDescriptionTooLong(int max);

  /// Agreement checkbox the publish button requires.
  ///
  /// In ko, this message translates to:
  /// **'부적절하거나 저작권을 침해하는 내용은 공개하지 않을게요'**
  String get publishAgreement;

  /// Button that publishes a deck.
  ///
  /// In ko, this message translates to:
  /// **'공개'**
  String get publishConfirm;

  /// After a deck was published.
  ///
  /// In ko, this message translates to:
  /// **'덱을 공개했어요'**
  String get published;

  /// After a deck was made private.
  ///
  /// In ko, this message translates to:
  /// **'덱을 비공개로 전환했어요'**
  String get unpublished;

  /// Today card's heading on the home screen, above the count.
  ///
  /// In ko, this message translates to:
  /// **'오늘 할 카드'**
  String get todayTitle;

  /// Unit after the large count on the today card: cards.
  ///
  /// In ko, this message translates to:
  /// **'장'**
  String get todayCountUnit;

  /// Home screen heading before the user has any deck.
  ///
  /// In ko, this message translates to:
  /// **'첫 덱을 만들어 볼까요?'**
  String get emptyHomeTitle;

  /// Home screen line under the first-deck heading.
  ///
  /// In ko, this message translates to:
  /// **'단어장 사진을 찍으면 카드를 바로 만들어 드려요. 직접 입력해도 돼요.'**
  String get emptyHomeBody;

  /// Empty home screen button that opens the new-deck sheet.
  ///
  /// In ko, this message translates to:
  /// **'직접 만들기'**
  String get createManually;

  /// Empty home screen button that opens the public decks.
  ///
  /// In ko, this message translates to:
  /// **'공개 덱 둘러보기'**
  String get browsePublicDecks;

  /// Title of the sheet that names a new deck.
  ///
  /// In ko, this message translates to:
  /// **'새 덱 만들기'**
  String get newDeckTitle;

  /// Line under the new-deck sheet's title.
  ///
  /// In ko, this message translates to:
  /// **'이름은 나중에도 바꿀 수 있어요.'**
  String get newDeckBody;

  /// Deck screen pill: how many cards the deck holds.
  ///
  /// In ko, this message translates to:
  /// **'카드 {count}'**
  String statCards(int count);

  /// Deck screen pill: how many cards are due now.
  ///
  /// In ko, this message translates to:
  /// **'복습 {count}'**
  String statReview(int count);

  /// Deck screen pill: how many new cards a session would study now.
  ///
  /// In ko, this message translates to:
  /// **'새 카드 {count}'**
  String statNew(int count);

  /// Sign-in screen note under the buttons; terms and privacy are the links termsOfService and privacyPolicy.
  ///
  /// In ko, this message translates to:
  /// **'계속하면 {terms}과 {privacy}에 동의하는 것으로 봐요.'**
  String consentNotice(String terms, String privacy);

  /// Link to the terms of service.
  ///
  /// In ko, this message translates to:
  /// **'이용약관'**
  String get termsOfService;

  /// Link to the privacy policy.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 처리방침'**
  String get privacyPolicy;

  /// Shown when the terms or privacy link could not be opened.
  ///
  /// In ko, this message translates to:
  /// **'링크를 열지 못했어요. 다시 시도해 주세요.'**
  String get linkNotOpened;

  /// Account screen footer: the app's version.
  ///
  /// In ko, this message translates to:
  /// **'버전 {version}'**
  String appVersion(String version);

  /// Today card when no card is due or new now; todayKeepStudying is its button.
  ///
  /// In ko, this message translates to:
  /// **'오늘 할 카드를 다 했어요'**
  String get todayDone;

  /// The today card's button when no card is left today: opens the study screen over every deck, on the completion card or on nothing to study.
  ///
  /// In ko, this message translates to:
  /// **'계속 학습'**
  String get todayKeepStudying;

  /// The bottom bar's first tab: today's cards.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get tabToday;

  /// The bottom bar's second tab: the user's decks.
  ///
  /// In ko, this message translates to:
  /// **'덱'**
  String get tabDecks;

  /// The bottom bar's third tab: the study record.
  ///
  /// In ko, this message translates to:
  /// **'기록'**
  String get tabRecord;

  /// What a screen reader calls the bottom bar of tabs.
  ///
  /// In ko, this message translates to:
  /// **'탭'**
  String get tabsLabel;

  /// The 기록 tab until its content arrives.
  ///
  /// In ko, this message translates to:
  /// **'학습 기록은 곧 여기에서 볼 수 있어요.'**
  String get recordComingSoon;

  /// The decks tab's action that enters selection mode, to study several decks in one session.
  ///
  /// In ko, this message translates to:
  /// **'선택'**
  String get selectDecks;

  /// The hint in the decks tab's search field, which filters decks by name.
  ///
  /// In ko, this message translates to:
  /// **'덱 검색'**
  String get searchDecks;

  /// The decks tab when no deck name holds the search.
  ///
  /// In ko, this message translates to:
  /// **'찾는 덱이 없어요. 다른 단어로 검색해 보세요.'**
  String get noDeckMatches;

  /// Under a deck row's progress bar: how many of its cards are mastered (interval of 21 days or more).
  ///
  /// In ko, this message translates to:
  /// **'{cards}장 중 {mastered}장 익힘'**
  String deckMastered(int cards, int mastered);

  /// Under 공개 덱 둘러보기 on the decks tab.
  ///
  /// In ko, this message translates to:
  /// **'다른 사람이 만든 덱을 내 덱으로 가져와요'**
  String get browsePublicDecksBody;

  /// Under 직접 만들기 in the new-deck sheet.
  ///
  /// In ko, this message translates to:
  /// **'이름을 정하고 카드를 하나씩 넣어요'**
  String get createManuallyBody;

  /// Under 사진으로 만들기 in the new-deck sheet.
  ///
  /// In ko, this message translates to:
  /// **'단어장 사진을 찍으면 카드를 찾아 드려요'**
  String get createFromPhotoBody;

  /// The new-deck sheet's option that opens the public decks.
  ///
  /// In ko, this message translates to:
  /// **'공개 덱에서 가져오기'**
  String get importFromPublic;

  /// Under 공개 덱에서 가져오기 in the new-deck sheet.
  ///
  /// In ko, this message translates to:
  /// **'다른 사람이 만든 덱을 복사해요'**
  String get importFromPublicBody;

  /// What a screen reader reads for a progress bar of mastered, learning and new cards.
  ///
  /// In ko, this message translates to:
  /// **'익힘 {mastered}장, 학습 중 {learning}장, 새 카드 {fresh}장'**
  String progressSemantics(int mastered, int learning, int fresh);

  /// Under the deck's name on its page: how many cards it holds.
  ///
  /// In ko, this message translates to:
  /// **'카드 {count}장'**
  String deckSummary(int count);

  /// Under a published deck's name on its page.
  ///
  /// In ko, this message translates to:
  /// **'카드 {count}장 · 공개'**
  String deckSummaryPublic(int count);

  /// What a screen reader calls the deck page's navy card.
  ///
  /// In ko, this message translates to:
  /// **'오늘 이 덱'**
  String get todayThisDeck;

  /// After the large count on a navy card: the unit and the minutes the cards take.
  ///
  /// In ko, this message translates to:
  /// **'장 · 약 {minutes}분'**
  String todayCountMinutes(int minutes);

  /// On the deck page's navy card: mastered cards of all.
  ///
  /// In ko, this message translates to:
  /// **'{mastered} / {total} 익힘'**
  String masteredOf(int mastered, int total);

  /// The deck page's button that studies the deck.
  ///
  /// In ko, this message translates to:
  /// **'학습하기'**
  String get studyDeck;

  /// The deck page's top bar button that opens the card search.
  ///
  /// In ko, this message translates to:
  /// **'카드 검색'**
  String get searchCardsAction;

  /// The button that closes the deck page's card search.
  ///
  /// In ko, this message translates to:
  /// **'검색 닫기'**
  String get closeSearch;

  /// The add-card sheet's option that opens the card editor.
  ///
  /// In ko, this message translates to:
  /// **'직접 입력'**
  String get addCardManually;

  /// Under 직접 입력 in the add-card sheet.
  ///
  /// In ko, this message translates to:
  /// **'문제와 답을 하나씩 적어요'**
  String get addCardManuallyBody;

  /// The add-card sheet's option that opens photo import for the deck.
  ///
  /// In ko, this message translates to:
  /// **'사진'**
  String get addCardPhoto;

  /// Under 사진 in the add-card sheet.
  ///
  /// In ko, this message translates to:
  /// **'단어장 사진에서 카드를 찾아요'**
  String get addCardPhotoBody;

  /// What a screen reader reads for a card row whose answer is hidden.
  ///
  /// In ko, this message translates to:
  /// **'{front}, 답 가려짐'**
  String cardAnswerHidden(String front);

  /// What a screen reader reads for a card row whose answer is shown.
  ///
  /// In ko, this message translates to:
  /// **'{front}, 답 {back}'**
  String cardAnswerShown(String front, String back);

  /// What a screen reader reads for the today card's goal ring.
  ///
  /// In ko, this message translates to:
  /// **'하루 목표 {goal}장 중 {done}장'**
  String goalRingSemantics(int done, int goal);

  /// On the today card: how much of the day's goal is done.
  ///
  /// In ko, this message translates to:
  /// **'하루 목표 {goal}장 중 {done}장 했어요'**
  String goalLine(int done, int goal);

  /// On the done card: the day's goal was reached.
  ///
  /// In ko, this message translates to:
  /// **'목표 {goal}장 달성'**
  String goalReached(int goal);

  /// A streak chip: study days in a row with an answer.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 연속'**
  String streakDays(int days);

  /// Heading of the forecast of cards due on each of the next seven study days.
  ///
  /// In ko, this message translates to:
  /// **'앞으로 7일'**
  String get forecastTitle;

  /// Beside the forecast's heading: tomorrow's cards and the seven days' total.
  ///
  /// In ko, this message translates to:
  /// **'내일 {tomorrow}장 · 이번 주 {week}장'**
  String forecastSummary(int tomorrow, int week);

  /// Beside the forecast's heading on the done card: the seven days' total.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 {week}장'**
  String forecastWeek(int week);

  /// The forecast's label for today.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get forecastToday;

  /// The forecast's label for tomorrow.
  ///
  /// In ko, this message translates to:
  /// **'내일'**
  String get forecastTomorrow;

  /// One day of the forecast as a screen reader reads it.
  ///
  /// In ko, this message translates to:
  /// **'{day} {count}장'**
  String forecastDay(String day, int count);

  /// Heading over the decks that hold cards for today.
  ///
  /// In ko, this message translates to:
  /// **'오늘 할 덱'**
  String get todayDecks;

  /// A today's-deck row: how many of its cards are left today.
  ///
  /// In ko, this message translates to:
  /// **'{count}장'**
  String deckDueCount(int count);

  /// What a screen reader reads for a today's-deck row, which studies the deck.
  ///
  /// In ko, this message translates to:
  /// **'{name}, 오늘 {count}장 학습'**
  String studyDeckToday(String name, int count);

  /// On the done card: when the next cards fall due, how many, and their minutes.
  ///
  /// In ko, this message translates to:
  /// **'다음 복습은 {day} · {cards}장, 약 {minutes}분'**
  String nextReview(String day, int cards, int minutes);

  /// On the done card when no card falls due in the next seven days.
  ///
  /// In ko, this message translates to:
  /// **'앞으로 7일 동안 복습할 카드가 없어요'**
  String get noNextReview;
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
