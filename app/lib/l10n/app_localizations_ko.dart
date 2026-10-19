// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'smartman';

  @override
  String get newDeck => '새 덱';

  @override
  String get deckActions => '덱 작업';

  @override
  String get renameDeck => '덱 이름 바꾸기';

  @override
  String get deleteDeck => '덱 삭제';

  @override
  String deleteDeckTitle(String name) {
    return '\"$name\" 덱을 삭제할까요?';
  }

  @override
  String deleteDeckBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '카드 $count장도 함께 삭제돼요.',
      zero: '이 덱에는 카드가 없어요.',
    );
    return '$_temp0';
  }

  @override
  String get deckName => '덱 이름';

  @override
  String get deckNameRequired => '이름을 입력하세요';

  @override
  String get noCards => '아직 카드가 없어요. 카드를 추가해 시작해 보세요.';

  @override
  String get newCard => '카드 추가';

  @override
  String get editCard => '카드 편집';

  @override
  String get deleteCard => '카드 삭제';

  @override
  String get cardFront => '앞면';

  @override
  String get cardBack => '뒷면';

  @override
  String get cardSideRequired => '내용을 입력하세요';

  @override
  String get blank => '빈칸';

  @override
  String get wholeCard => '카드';

  @override
  String get sensesEditNote => '앞면을 고치면 [명] 같은 표시도 글자로 저장돼요.';

  @override
  String get cardKindBasic => '기본';

  @override
  String get cardKindWord => '단어';

  @override
  String get cardKindCloze => '빈칸';

  @override
  String get clozeWordsHint => '빈칸으로 할 낱말을 눌러요';

  @override
  String clozeWord(String word) {
    return '$word';
  }

  @override
  String clozeWordBlank(String word) {
    return '$word, 빈칸';
  }

  @override
  String get clozeBlankRequired => '빈칸으로 할 낱말을 하나 이상 골라 주세요';

  @override
  String get cardKindTable => '표';

  @override
  String get tableNameHint => '표의 이름';

  @override
  String get tableModeLabel => '표 편집 방식';

  @override
  String get tableModeCells => '칸 입력';

  @override
  String get tableModeBlanks => '빈칸 고르기';

  @override
  String get tableCellsHint => '제목과 칸에 내용을 적어요';

  @override
  String get tableBlanksHint => '빈칸으로 할 칸을 눌러요';

  @override
  String tableHeaderCell(int column) {
    return '$column열 제목';
  }

  @override
  String tableCell(int row, int column) {
    return '$row행 $column열';
  }

  @override
  String get tableEmptyCell => '내용 없음';

  @override
  String get tableMakeBlank => '빈칸으로';

  @override
  String get tableClearBlank => '빈칸 해제';

  @override
  String get addRow => '행 추가';

  @override
  String get addColumn => '열 추가';

  @override
  String deleteRow(int row) {
    return '$row행 지우기';
  }

  @override
  String deleteColumn(int column) {
    return '$column열 지우기';
  }

  @override
  String get tableBlankRequired => '빈칸으로 할 칸을 하나 이상 골라 주세요';

  @override
  String get tableBlankEmpty => '빈칸으로 고른 칸에 내용을 적어 주세요';

  @override
  String get cardKindLabel => '카드 종류';

  @override
  String senseHeading(int number) {
    return '뜻 $number';
  }

  @override
  String get senseMeaning => '뜻';

  @override
  String get senseExamples => '예문';

  @override
  String get senseExamplesHint => '한 줄에 하나씩, 없으면 비워 두세요';

  @override
  String get senseMeaningRequired => '뜻을 적어 주세요';

  @override
  String get addSense => '뜻 추가';

  @override
  String moveSenseUp(int number) {
    return '$number번째 뜻을 위로';
  }

  @override
  String moveSenseDown(int number) {
    return '$number번째 뜻을 아래로';
  }

  @override
  String deleteSense(int number) {
    return '$number번째 뜻 지우기';
  }

  @override
  String get addLabel => '표시 추가';

  @override
  String removeLabel(String label) {
    return '[$label] 표시 지우기';
  }

  @override
  String get labelSheetBody => '품사를 고르거나 다른 표시를 적어요.';

  @override
  String get otherLabel => '다른 표시';

  @override
  String get otherLabelHint => '예: 사물';

  @override
  String get addOtherLabel => '이 표시 추가';

  @override
  String partOfSpeechChoice(String short, String name) {
    return '[$short] $name';
  }

  @override
  String partOfSpeechName(String category) {
    String _temp0 = intl.Intl.selectLogic(category, {
      'noun': '명사',
      'verb': '동사',
      'adjective': '형용사',
      'adverb': '부사',
      'pronoun': '대명사',
      'preposition': '전치사',
      'conjunction': '접속사',
      'interjection': '감탄사',
      'determiner': '관사',
      'numeral': '수사',
      'particle': '조사',
      'auxiliary': '조동사',
      'classifier': '양사',
      'phrase': '구',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get duplicateTitle => '이 덱에 이미 있는 카드예요';

  @override
  String get duplicateBody => '대소문자와 띄어쓰기는 구분하지 않아요.';

  @override
  String get openExistingCard => '기존 카드 열기';

  @override
  String get addAnyway => '그래도 추가';

  @override
  String get saveAnyway => '그래도 저장';

  @override
  String unsupportedContent(String type) {
    return '[이 버전에서 표시할 수 없는 내용: $type]';
  }

  @override
  String get storageFailure => '기기 저장소를 읽거나 쓰지 못했어요. 다시 시도해 주세요.';

  @override
  String get unreadableCard => '이 덱에 읽을 수 없는 카드가 있어요.';

  @override
  String get cancel => '취소';

  @override
  String get save => '저장';

  @override
  String get create => '만들기';

  @override
  String get rename => '이름 바꾸기';

  @override
  String get delete => '삭제';

  @override
  String todayCards(int count) {
    return '오늘 할 카드 $count장';
  }

  @override
  String get studyAll => '모두 학습';

  @override
  String get know => '안다';

  @override
  String get dontKnow => '모른다';

  @override
  String get close => '닫기';

  @override
  String studyProgress(int answered, int total) {
    return '$answered/$total';
  }

  @override
  String studyProgressSemantics(int answered, int total) {
    return '$total장 중 $answered장 응답함';
  }

  @override
  String currentCardSemantics(String front) {
    return '앞면: $front';
  }

  @override
  String get showBack => '뒷면 보기';

  @override
  String get hideBack => '뒷면 가리기';

  @override
  String previousCardSemantics(
    String front,
    String back,
    String answer,
    String changed,
  ) {
    String _temp0 = intl.Intl.selectLogic(changed, {
      'yes': '. 수정됨',
      'other': '',
    });
    return '앞면: $front. 뒷면: $back. 응답: $answer$_temp0';
  }

  @override
  String get showWholeCard => '카드 전체 보기';

  @override
  String get changeToKnow => '안다로 바꾸기';

  @override
  String get changeToDontKnow => '모른다로 바꾸기';

  @override
  String get changingToKnow => '안다로 바꿔요';

  @override
  String get changingToDontKnow => '모른다로 바꿔요';

  @override
  String get previousPlaceholder => '응답한 카드가 여기에 쌓여요';

  @override
  String get earlierCard => '지난번 마지막 카드';

  @override
  String resumeToast(int cards, int minutes) {
    return '이어서 해요 · 남은 $cards장 · 약 $minutes분';
  }

  @override
  String get studyCoachKnow => '알면 오른쪽으로 밀어요';

  @override
  String get studyCoachDontKnow => '모르면 왼쪽으로 밀어요';

  @override
  String get studyCoachRedecide => '응답한 카드는 위로 올라와요. 밀어서 응답을 바꿀 수 있어요';

  @override
  String get studyCoachReplay => '안내 다시 보기';

  @override
  String get studyCoachSampleFront => 'deadline';

  @override
  String get studyCoachSampleBack => '마감 기한';

  @override
  String get answerNotSaved => '응답을 기기에 저장하지 못했어요. 이 카드의 일정은 그대로예요.';

  @override
  String get settingNotSaved => '공부 시간을 기기에 저장하지 못했어요. 다시 시도해 주세요.';

  @override
  String get studyComplete => '오늘 학습 완료';

  @override
  String get nothingToStudyToday => '오늘은 학습할 카드가 없어요';

  @override
  String completionMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String completionStreak(int days) {
    return '$days일';
  }

  @override
  String completionSemantics(int know, int dontKnow, int minutes, int days) {
    return '안다 $know, 모른다 $dontKnow, $minutes분, $days일 연속';
  }

  @override
  String get studyOn => '학습하기';

  @override
  String get noCardsLeft => '더 학습할 카드가 없어요';

  @override
  String get stopStudying => '그만하기';

  @override
  String get schedulingFailure => '이 카드의 다음 복습 일정을 계산하지 못했어요. 일정은 그대로예요.';

  @override
  String get account => '계정';

  @override
  String get accountTitle => '계정';

  @override
  String get welcomeBody => '밀어서 응답하고,\n잊을 때쯤 다시 만나는 암기 카드';

  @override
  String get signInWithGoogle => 'Google로 계속하기';

  @override
  String get signInWithAppleSoon => 'Apple로 계속하기 · 준비 중';

  @override
  String get signingIn => '로그인 중';

  @override
  String get signedIn => '로그인했어요';

  @override
  String get signOut => '로그아웃';

  @override
  String get signingOut => '로그아웃 중';

  @override
  String get accountOffline => '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.';

  @override
  String get accountMisconfigured => '이 앱의 로그인 설정에 문제가 있어 로그인할 수 없어요.';

  @override
  String get accountRejected => 'Google 로그인이 거부됐어요. 다시 시도해 주세요.';

  @override
  String get accountSection => '계정';

  @override
  String get displaySection => '화면';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String myDecks(int count) {
    return '내 덱 $count';
  }

  @override
  String cardCount(int count) {
    return '카드 $count장';
  }

  @override
  String todayChip(int count) {
    return '오늘 $count';
  }

  @override
  String get backlogPaused => '밀린 복습을 마칠 때까지 새 카드는 쉬어요.';

  @override
  String get searchCards => '검색';

  @override
  String get noMatches => '찾는 카드가 없어요. 다른 단어로 검색해 보세요.';

  @override
  String get saveAndNext => '저장하고 다음 카드';

  @override
  String get deleteCardTitle => '이 카드를 삭제할까요?';

  @override
  String get deleteCardBody => '이 카드의 학습 기록도 함께 삭제돼요.';

  @override
  String get unsyncedChangesTitle => '동기화되지 않은 변경이 있어요';

  @override
  String get unsyncedChangesBody => '로그아웃하면 이 기기에서 지워지고 다른 기기에서는 볼 수 없어요.';

  @override
  String get signOutAnyway => '그래도 로그아웃';

  @override
  String get dataNotCleared => '이 기기의 데이터를 지우지 못했어요. 다른 계정으로 로그인하면 지워져요.';

  @override
  String get deleteAccount => '계정 삭제';

  @override
  String get deleteAccountNote =>
      '계정을 삭제하면 서버와 이 기기에 있는 카드와 기록이 모두 지워져요. 되돌릴 수 없어요.';

  @override
  String get deleteAccountTitle => '계정을 삭제할까요?';

  @override
  String get deleteAccountBody =>
      '서버와 이 기기의 덱, 카드, 학습 기록이 모두 지워지고, 다른 사람이 복사한 덱과 Google 계정은 남아요.';

  @override
  String get deletingAccount => '계정 삭제 중';

  @override
  String get deleteAccountRejected => '계정을 삭제하지 못했어요. 다시 시도해 주세요.';

  @override
  String get syncSyncing => '동기화 중';

  @override
  String get syncSynced => '동기화됨';

  @override
  String get syncOffline => '오프라인 · 연결되면 동기화해요';

  @override
  String get syncFailed => '동기화하지 못했어요';

  @override
  String get syncRetry => '다시 시도';

  @override
  String get photoTargetTitle => '추가할 덱';

  @override
  String get photoCamera => '사진 찍기';

  @override
  String get photoAlbum => '앨범에서 고르기';

  @override
  String get photoAccessDenied => '카메라나 앨범 사용이 허용되지 않았어요. 설정에서 허용해 주세요.';

  @override
  String get cameraUnavailable => '카메라를 열 수 없어요. 앨범에서 사진을 골라 주세요.';

  @override
  String get openSettings => '설정 열기';

  @override
  String get settingsNotOpened => '설정을 열지 못했어요. 설정 앱에서 직접 허용해 주세요.';

  @override
  String get photoThumbnail => '찍은 사진';

  @override
  String get extractingTitle => '카드를 찾고 있어요';

  @override
  String get extractingNote => '사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요';

  @override
  String get duplicateSkip => '건너뛰기';

  @override
  String get duplicateMergeBack => '뒷면 합치기';

  @override
  String get duplicateAddNew => '새 카드로 추가';

  @override
  String get retake => '다시 찍기';

  @override
  String get pickAnother => '다른 사진 고르기';

  @override
  String get makeDeck => '덱 만들기';

  @override
  String get photoCameraBody => '단어장을 찍으면 카드를 찾아 드려요';

  @override
  String get photoAlbumBody => '고른 사진에서 카드를 찾아 드려요';

  @override
  String get retry => '다시 시도';

  @override
  String get extractionOffline => '인터넷에 연결되지 않았어요. 연결을 확인하고 다시 시도해 주세요.';

  @override
  String get photoRefused => '이 사진은 보낼 수 없어요. 다시 찍거나 다른 사진을 골라 주세요.';

  @override
  String get noCardsFound => '카드를 찾지 못했어요. 더 밝고 반듯하게 찍어 보세요.';

  @override
  String get accountSuspended => '이 계정은 이용이 정지됐어요. 문의는 sauce@garam.sh로 보내 주세요.';

  @override
  String dailyLimitReachedOf(int limit) {
    return '오늘 사진으로 만들 수 있는 $limit장을 다 썼어요. 내일 다시 시도해 주세요.';
  }

  @override
  String get modelFailed => '카드를 읽지 못했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get signInRequired => '로그인이 필요해요. 계정 화면에서 다시 로그인해 주세요.';

  @override
  String get serviceFailed => '지금은 사진으로 카드를 만들 수 없어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get photoUnreadable => '이 사진을 읽을 수 없어요. 다른 사진을 골라 주세요.';

  @override
  String get deckDeleted => '이 덱은 삭제됐어요. 다른 덱을 골라 주세요.';

  @override
  String get browse => '공개 덱';

  @override
  String get publish => '공개하기';

  @override
  String get unpublish => '비공개로 전환';

  @override
  String get publishNeedsNetwork => '인터넷에 연결되면 바꿀 수 있어요';

  @override
  String get publicChip => '공개';

  @override
  String get searchPublicDecks => '덱 이름이나 설명으로 검색';

  @override
  String get sortNewest => '최신순';

  @override
  String get sortMostCopied => '가져오기 많은 순';

  @override
  String publicDeckLine(String owner, int cards, int copies) {
    return '$owner · 카드 $cards장 · 가져오기 $copies회';
  }

  @override
  String get noPublicDecks => '아직 공개된 덱이 없어요. 내 덱을 공개해 처음으로 나눠 보세요.';

  @override
  String get noPublicMatches => '찾는 덱이 없어요. 다른 단어로 검색해 보세요.';

  @override
  String get browseOffline => '인터넷에 연결되지 않았어요. 연결되면 공개 덱을 볼 수 있어요.';

  @override
  String get loading => '불러오는 중';

  @override
  String get sharingOffline => '인터넷에 연결되지 않았어요. 연결을 확인하고 다시 시도해 주세요.';

  @override
  String get sharingRejected => '요청이 거절됐어요. 계정 화면에서 다시 로그인한 뒤 시도해 주세요.';

  @override
  String get sharingFailed => '지금은 처리할 수 없어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get deckNoLongerPublic => '이 덱은 더 이상 공개되어 있지 않아요.';

  @override
  String get copyToMyDecks => '내 덱으로 가져오기';

  @override
  String previewFirstCards(int shown, int total) {
    return '카드 $total장 중 처음 $shown장';
  }

  @override
  String get reportDeck => '신고하기';

  @override
  String get blockUser => '이 사용자 차단';

  @override
  String get reportTitle => '신고 이유';

  @override
  String get reportInappropriate => '부적절한 내용';

  @override
  String get reportSpam => '스팸';

  @override
  String get reportCopyright => '저작권 침해';

  @override
  String get reportOther => '기타';

  @override
  String get reported => '신고했어요. 검토할게요.';

  @override
  String get alreadyReported => '이미 신고한 덱이에요.';

  @override
  String blockTitle(String name) {
    return '$name 님을 차단할까요?';
  }

  @override
  String get blockBody => '이 사용자의 덱이 둘러보기에 더 이상 나오지 않아요.';

  @override
  String get block => '차단';

  @override
  String blocked(String name) {
    return '$name 님을 차단했어요.';
  }

  @override
  String get copyAsNewDeck => '새 덱으로';

  @override
  String get copyIntoExistingDeck => '기존 덱에 추가';

  @override
  String copyNewDeckHint(String name) {
    return '\"$name\" 덱을 새로 만들어 모든 카드를 가져와요.';
  }

  @override
  String get copyTargetDeck => '덱';

  @override
  String get copyDuplicates => '이미 있는 카드는';

  @override
  String get copyConfirm => '가져오기';

  @override
  String copiedCards(String deck, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '\"$deck\"에 카드 $count장을 가져왔어요',
      zero: '\"$deck\"에 새로 가져온 카드가 없어요',
    );
    return '$_temp0';
  }

  @override
  String publishTitle(String name) {
    return '\"$name\" 공개하기';
  }

  @override
  String get displayName => '공개 이름';

  @override
  String get displayNameHelp => '공개한 덱에 이 이름이 표시돼요. 이메일은 표시되지 않아요.';

  @override
  String get displayNameLength => '2~20자로 입력하세요';

  @override
  String get deckDescription => '설명 (선택)';

  @override
  String deckDescriptionTooLong(int max) {
    return '$max자 이내로 입력하세요';
  }

  @override
  String get publishAgreement => '부적절하거나 저작권을 침해하는 내용은 공개하지 않을게요';

  @override
  String get publishConfirm => '공개';

  @override
  String get published => '덱을 공개했어요';

  @override
  String get unpublished => '덱을 비공개로 전환했어요';

  @override
  String get todayTitle => '오늘 할 카드';

  @override
  String get noCardsTitle => '첫 카드를 만들어 볼까요?';

  @override
  String get noCardsBody => '덱에 카드를 추가해 시작해요';

  @override
  String get openDeck => '덱 열기';

  @override
  String get addCardsInDecks => '덱에서 카드 추가하기';

  @override
  String get emptyHomeTitle => '첫 덱을 만들어 볼까요?';

  @override
  String get emptyHomeBody => '단어장 사진을 찍으면 카드를 바로 만들어 드려요. 직접 입력해도 돼요.';

  @override
  String get createManually => '직접 만들기';

  @override
  String get browsePublicDecks => '공개 덱 둘러보기';

  @override
  String get newDeckTitle => '새 덱 만들기';

  @override
  String get newDeckBody => '이름은 나중에도 바꿀 수 있어요.';

  @override
  String consentNotice(String terms, String privacy) {
    return '계속하면 $terms과 $privacy에 동의하는 것으로 봐요.';
  }

  @override
  String get termsOfService => '이용약관';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get linkNotOpened => '링크를 열지 못했어요. 다시 시도해 주세요.';

  @override
  String appVersion(String version) {
    return '버전 $version';
  }

  @override
  String get todayDone => '오늘 할 카드를 다 했어요';

  @override
  String get todayStudy => '학습하기';

  @override
  String get tabToday => '오늘';

  @override
  String get tabDecks => '덱';

  @override
  String get tabRecord => '기록';

  @override
  String get tabsLabel => '탭';

  @override
  String get searchDecks => '덱 검색';

  @override
  String get noDeckMatches => '찾는 덱이 없어요. 다른 단어로 검색해 보세요.';

  @override
  String deckMastered(int cards, int mastered) {
    return '$cards장 중 $mastered장 익힘';
  }

  @override
  String get browsePublicDecksBody => '다른 사람이 만든 덱을 내 덱으로 가져와요';

  @override
  String get createManuallyBody => '이름을 정하고 카드를 하나씩 넣어요';

  @override
  String progressSemantics(int mastered, int learning, int fresh) {
    return '익힘 $mastered장, 학습 중 $learning장, 새 카드 $fresh장';
  }

  @override
  String deckSummary(int count) {
    return '카드 $count장';
  }

  @override
  String deckSummaryPublic(int count) {
    return '카드 $count장 · 공개';
  }

  @override
  String get todayThisDeck => '오늘 이 덱';

  @override
  String todayCountMinutes(int minutes) {
    return '장 · 약 $minutes분';
  }

  @override
  String masteredOf(int mastered, int total) {
    return '$mastered / $total 익힘';
  }

  @override
  String get studyDeck => '학습하기';

  @override
  String get searchCardsAction => '카드 검색';

  @override
  String get closeSearch => '검색 닫기';

  @override
  String get addCardManuallyBody => '앞면과 뒷면을 하나씩 적어요';

  @override
  String cardListTitle(int count) {
    return '카드 $count';
  }

  @override
  String get showMeanings => '뜻 보기';

  @override
  String cardBackHidden(String front) {
    return '$front, 뒷면 가려짐';
  }

  @override
  String cardBackShown(String front, String back) {
    return '$front, 뒷면 $back';
  }

  @override
  String goalRingSemantics(int done, int goal) {
    return '하루 목표 $goal장 중 $done장';
  }

  @override
  String statusStreak(int days) {
    return '$days일째 이어 가는 중이에요';
  }

  @override
  String get statusWaiting => '오늘의 첫 카드를 기다리고 있어요';

  @override
  String get statusAlmostDone => '거의 다 왔어요';

  @override
  String get statusPastHalf => '절반을 넘었어요';

  @override
  String get statusStarted => '좋은 출발이에요';

  @override
  String goalReached(int goal) {
    return '목표 $goal장 달성';
  }

  @override
  String streakDays(int days) {
    return '$days일 연속';
  }

  @override
  String get dayToday => '오늘';

  @override
  String get dayTomorrow => '내일';

  @override
  String dayCount(String day, int count) {
    return '$day $count장';
  }

  @override
  String get todayDecks => '오늘 할 덱';

  @override
  String deckDueCount(int count) {
    return '$count장';
  }

  @override
  String studyDeckToday(String name, int count) {
    return '$name, 오늘 $count장 학습';
  }

  @override
  String nextReview(String day, int cards, int minutes) {
    return '다음 복습은 $day · $cards장, 약 $minutes분';
  }

  @override
  String get noNextReview => '앞으로 7일 동안 복습할 카드가 없어요';

  @override
  String get backlogTitle => '다시 시작하면 돼요';

  @override
  String backlogBody(int count) {
    return '밀린 복습 $count장을 급한 것부터 해요. 새 카드는 잠시 쉬어요.';
  }

  @override
  String backlogStudy(int count, int minutes) {
    return '$count장 학습 · 약 $minutes분';
  }

  @override
  String catchUpTitle(int perDay, int days) {
    return '하루 $perDay장씩 하면 $days일이면 따라잡아요';
  }

  @override
  String catchUpNote(int perDay) {
    return '하루 $perDay장씩 했을 때 남는 밀린 복습이에요';
  }

  @override
  String catchUpSemantics(String days) {
    return '밀린 복습 예상: $days';
  }

  @override
  String get statsPeriod => '기간';

  @override
  String get statsPeriodWeek => '7일';

  @override
  String get statsPeriodMonth => '30일';

  @override
  String get statsPeriodAll => '전체';

  @override
  String get retentionTitle => '복습에서 맞힌 비율';

  @override
  String retentionPercent(int percent) {
    return '$percent%';
  }

  @override
  String get retentionTarget => '목표';

  @override
  String retentionBelow(int points) {
    return '목표보다 $points%p 낮아요';
  }

  @override
  String retentionAbove(int points) {
    return '목표보다 $points%p 높아요';
  }

  @override
  String get retentionOnTarget => '목표만큼 맞혔어요';

  @override
  String retentionTargetLine(int percent) {
    return '목표 $percent%';
  }

  @override
  String retentionDaysAgo(int days) {
    return '$days일 전';
  }

  @override
  String get statsToday => '오늘';

  @override
  String get retentionEmpty => '이 기간에 복습한 카드가 없어요.';

  @override
  String retentionSemantics(int target, String days) {
    return '복습에서 맞힌 비율, 목표 $target%: $days';
  }

  @override
  String retentionDay(String date, int percent) {
    return '$date $percent%';
  }

  @override
  String get recallTitle => '지금 기억하고 있을 확률';

  @override
  String recallMean(int percent) {
    return '평균 $percent%';
  }

  @override
  String get recallStrong => '단단함';

  @override
  String get recallFair => '보통';

  @override
  String get recallFading => '곧 잊음';

  @override
  String statsCards(int count) {
    return '$count장';
  }

  @override
  String recallSemantics(
    int total,
    int strong,
    int fair,
    int fading,
    int mean,
  ) {
    return '$total장 중 단단함 $strong장, 보통 $fair장, 곧 잊음 $fading장, 평균 $mean%';
  }

  @override
  String get recallEmpty => '아직 복습한 카드가 없어요.';

  @override
  String get masteredTitle => '익힌 카드';

  @override
  String masteredGain(int count) {
    return '4주 +$count장';
  }

  @override
  String masteredSemantics(String counts) {
    return '주별 익힌 카드, 8주 전부터 이번 주까지: $counts';
  }

  @override
  String get studyDaysTitle => '학습한 날';

  @override
  String studyDaysStreak(int current, int best) {
    return '$current일 연속 · 최고 $best일';
  }

  @override
  String studyDaysSemantics(int count, String days) {
    return '최근 12주 동안 $count일 학습했어요: $days';
  }

  @override
  String get studyDaysNone => '최근 12주 동안 학습한 날이 없어요';

  @override
  String studyDay(String date, int count) {
    return '$date $count장';
  }

  @override
  String get masteredEmpty => '아직 익힌 카드가 없어요.';

  @override
  String get newDeckEntryBody => '새 덱을 시작할 방법을 골라요';

  @override
  String importTitleWords(int count) {
    return '단어 $count개를 찾았어요';
  }

  @override
  String importTitleCards(int count) {
    return '카드 $count장을 만들었어요';
  }

  @override
  String importDeck(String name) {
    return '덱 \'$name\'에 추가돼요';
  }

  @override
  String importAdd(int count) {
    return '카드 $count장 추가';
  }

  @override
  String importSection(String topic, int count) {
    return '$topic $count';
  }

  @override
  String importIdentifySection(String topic) {
    return '판별 · $topic';
  }

  @override
  String get importForward => '단어 → 뜻';

  @override
  String get importBackward => '뜻 → 단어';

  @override
  String get importBoth => '양쪽 다 만들기';

  @override
  String get importBothShort => '양쪽 다';

  @override
  String get importFirstSense => '첫 뜻만';

  @override
  String get importShowPos => '품사 표시';

  @override
  String get importShowPronunciation => '발음 표시';

  @override
  String get importShowExtras => '유의어 등 표시';

  @override
  String get importNoteForward => '앞 → 뒤';

  @override
  String get importNoteSwapped => '뒤 → 앞';

  @override
  String get importSwap => '앞뒤 바꾸기';

  @override
  String get importDropSection => '이 묶음 빼기';

  @override
  String get importKeepSection => '이 묶음 넣기';

  @override
  String importFormMenu(String topic, String form) {
    return '$topic 카드 모양, $form';
  }

  @override
  String importRow(String front, String back) {
    return '$front, $back. 눌러서 고쳐요';
  }

  @override
  String importInclude(String front) {
    return '$front 넣기';
  }

  @override
  String get importRemove => '빼기';

  @override
  String get importInDeck => '이미 덱에 있어요';

  @override
  String get editTitle => '카드 고치기';

  @override
  String get editFront => '앞면';

  @override
  String get editBack => '뒷면';

  @override
  String get editSenses => '뜻';

  @override
  String editSense(int number) {
    return '$number번째 뜻';
  }

  @override
  String editKeepSense(int number) {
    return '$number번째 뜻 넣기';
  }

  @override
  String editMoveSense(int number) {
    return '$number번째 뜻 옮기기';
  }

  @override
  String get editDone => '완료';

  @override
  String coachStep(int step, int total) {
    return '사용 방법, $total단계 중 $step단계';
  }

  @override
  String get coachSkip => '건너뛰기';

  @override
  String get coachNext => '다음';

  @override
  String get coachStart => '시작하기';

  @override
  String dailyMinutesControl(int minutes) {
    return '하루 $minutes분';
  }

  @override
  String dailyMinutesControlSemantics(int minutes) {
    return '하루 공부 시간 $minutes분, 바꾸기';
  }

  @override
  String get dailyMinutesTitle => '하루 공부 시간';

  @override
  String get dailyMinutesFirstTitle => '하루 몇 분 공부할까요?';

  @override
  String get dailyMinutesBody => '복습을 먼저 하고, 남는 시간에 새 카드를 시작해요.';

  @override
  String dailyMinutesChoice(int minutes) {
    return '$minutes분';
  }

  @override
  String get dailyMinutesCustom => '직접 정하기';

  @override
  String dailyMinutesCustomValue(int minutes) {
    return '직접 · $minutes분';
  }

  @override
  String get dailyMinutesLess => '5분 줄이기';

  @override
  String get dailyMinutesMore => '5분 늘리기';

  @override
  String dailyMinutesToday(int fresh, int reviews) {
    return '오늘 새 카드 약 $fresh장 · 복습 $reviews장';
  }

  @override
  String dailyMinutesForecast(int cards, String date) {
    return '이대로면 남은 새 카드 $cards장을 $date쯤 다 시작해요';
  }

  @override
  String dailyMinutesForecastToday(int cards) {
    return '남은 새 카드 $cards장을 오늘 다 시작해요';
  }

  @override
  String get dailyMinutesNoTime => '이 시간은 복습으로 차서 새 카드는 시작하지 않아요';

  @override
  String get dailyMinutesAllStarted => '새 카드를 모두 시작했어요';

  @override
  String get dailyMinutesSkip => '건너뛰기';

  @override
  String completionTomorrow(int minutes) {
    return '내일도 하루 $minutes분';
  }

  @override
  String get completionChange => '바꾸기';

  @override
  String completionTomorrowSemantics(int minutes) {
    return '내일도 하루 $minutes분, 바꾸기';
  }

  @override
  String get settingsStudy => '공부';

  @override
  String studyExtra(int count) {
    return '추가 $count장';
  }

  @override
  String studyExtraSemantics(int count) {
    return '오늘 계획 밖으로 $count장 더 공부함';
  }

  @override
  String todayExtra(int count) {
    return '오늘 $count장 더 했어요';
  }

  @override
  String get weekTitle => '지난 7일';

  @override
  String weekSummary(int cards, int minutes) {
    return '이번 주 $cards장 · $minutes분';
  }

  @override
  String weekSemantics(int cards, int minutes) {
    return '지난 7일 동안 $cards장을 $minutes분 공부했어요';
  }

  @override
  String get weekOpenRecord => '기록 열기';
}
