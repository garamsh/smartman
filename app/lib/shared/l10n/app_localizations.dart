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
  /// **'아직 덱이 없어요. 새 덱을 만들어 시작해 보세요.'**
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
  /// **'{count, plural, =0{이 덱에는 카드가 없어요.} other{카드 {count}장도 함께 삭제돼요.}}'**
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
  /// **'{answered} / {total}'**
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

  /// Accessibility hint of tapping a card answered earlier: it changes the answer.
  ///
  /// In ko, this message translates to:
  /// **'답 바꾸기'**
  String get toggleAnswer;

  /// Accessibility hint of long-pressing a card answered earlier: it opens the whole card.
  ///
  /// In ko, this message translates to:
  /// **'카드 전체 보기'**
  String get showWholeCard;

  /// Small label on a card answered earlier whose answer differs from the one first given.
  ///
  /// In ko, this message translates to:
  /// **'수정됨'**
  String get answerChanged;

  /// Heading of the end-of-session summary.
  ///
  /// In ko, this message translates to:
  /// **'학습 끝'**
  String get sessionSummaryTitle;

  /// Shown in the summary when the deck had nothing due and no new card.
  ///
  /// In ko, this message translates to:
  /// **'지금 학습할 카드가 없어요.'**
  String get nothingToStudy;

  /// Summary line: distinct cards answered in the session.
  ///
  /// In ko, this message translates to:
  /// **'학습한 카드: {count}장'**
  String cardsStudied(int count);

  /// Summary line: how many answers stand as Know.
  ///
  /// In ko, this message translates to:
  /// **'안다: {count}번'**
  String knowCount(int count);

  /// Summary line: how many answers stand as Don't know.
  ///
  /// In ko, this message translates to:
  /// **'모른다: {count}번'**
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
  /// **'답을 기기에 저장하지 못했어요. 이 카드의 일정은 그대로예요.'**
  String get answerNotSaved;

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

  /// Sign-in screen line under the app name, saying what the app does.
  ///
  /// In ko, this message translates to:
  /// **'밀어서 답하고, 잊을 때쯤 다시 보여 주는 암기 카드.'**
  String get welcomeBody;

  /// Button that opens Google's account picker to sign in.
  ///
  /// In ko, this message translates to:
  /// **'Google로 로그인'**
  String get signInWithGoogle;

  /// Disabled sign-in screen button holding the place of Apple sign-in, which is not available yet.
  ///
  /// In ko, this message translates to:
  /// **'Apple로 로그인 (준비 중)'**
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

  /// Line under the today count: how many of the cards are due reviews and how many are new.
  ///
  /// In ko, this message translates to:
  /// **'복습 {review} · 새 카드 {fresh}'**
  String todayBreakdown(int review, int fresh);

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

  /// Line under a deck name: its cards, and how many due reviews and new cards a session would study now.
  ///
  /// In ko, this message translates to:
  /// **'카드 {cards}장 · 오늘 복습 {review} · 새 카드 {fresh}'**
  String deckSummary(int cards, int review, int fresh);

  /// Card list button that studies the deck, with how many cards the session would study.
  ///
  /// In ko, this message translates to:
  /// **'학습 · {count}장'**
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

  /// Chip on a deck others can find.
  ///
  /// In ko, this message translates to:
  /// **'공개됨'**
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
