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
  String get cardFront => '문제';

  @override
  String get cardBack => '답';

  @override
  String get cardSideRequired => '내용을 입력하세요';

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
  String get clearSelection => '선택 해제';

  @override
  String decksSelected(int count) {
    return '$count개 선택됨';
  }

  @override
  String studySelected(int count) {
    return '학습 ($count)';
  }

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
    return '$total장 중 $answered장 답함';
  }

  @override
  String currentCardSemantics(String front) {
    return '앞면: $front';
  }

  @override
  String currentCardRevealedSemantics(String front, String back) {
    return '앞면: $front. 뒷면: $back';
  }

  @override
  String get showAnswer => '답 보기';

  @override
  String get hideAnswer => '답 가리기';

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
    return '앞면: $front. 뒷면: $back. 답: $answer$_temp0';
  }

  @override
  String get toggleAnswer => '답 바꾸기';

  @override
  String get showWholeCard => '카드 전체 보기';

  @override
  String get answerChanged => '수정됨';

  @override
  String get sessionSummaryTitle => '오늘 할 카드를 마쳤어요';

  @override
  String get nothingToStudy => '지금 학습할 카드가 없어요.';

  @override
  String get answerNotSaved => '답을 기기에 저장하지 못했어요. 이 카드의 일정은 그대로예요.';

  @override
  String get schedulingFailure => '이 카드의 다음 복습 일정을 계산하지 못했어요. 일정은 그대로예요.';

  @override
  String get account => '계정';

  @override
  String get accountTitle => '계정';

  @override
  String get welcomeBody => '밀어서 답하고,\n잊을 때쯤 다시 만나는 암기 카드';

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
  String todayBreakdown(int review, int fresh, int minutes) {
    return '복습 $review · 새 카드 $fresh · 약 $minutes분';
  }

  @override
  String myDecks(int count) {
    return '내 덱 $count';
  }

  @override
  String get selectHint => '길게 눌러 여러 덱 선택';

  @override
  String cardCount(int count) {
    return '카드 $count장';
  }

  @override
  String todayChip(int count) {
    return '오늘 $count';
  }

  @override
  String get createFromPhoto => '사진으로 만들기';

  @override
  String get addFromPhoto => '사진으로 추가';

  @override
  String get backlogPaused => '밀린 복습을 마칠 때까지 새 카드는 쉬어요.';

  @override
  String studyCount(int count) {
    return '학습하기 · $count장';
  }

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
  String get photoCaptureHint => '단어장이나 책 한 페이지를 틀 안에 맞춰 찍어 주세요';

  @override
  String photoTarget(String name) {
    return '추가할 덱 · $name';
  }

  @override
  String get photoTargetTitle => '추가할 덱';

  @override
  String get photoAlbum => '앨범에서 고르기';

  @override
  String get photoShutter => '사진 찍기';

  @override
  String get cameraDenied => '카메라 사용이 허용되지 않았어요. 설정에서 허용하거나 앨범에서 사진을 골라 주세요.';

  @override
  String get cameraUnavailable => '카메라를 열 수 없어요. 앨범에서 사진을 골라 주세요.';

  @override
  String get photoThumbnail => '찍은 사진';

  @override
  String get extractingTitle => '카드를 찾고 있어요';

  @override
  String get extractingNote => '사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요';

  @override
  String reviewTitle(int count) {
    return '카드 $count개를 찾았어요';
  }

  @override
  String reviewHint(String deck) {
    return '눌러서 고치고, 뺄 카드는 체크를 끄세요 · $deck';
  }

  @override
  String get detailLevelLabel => '카드에 담을 내용';

  @override
  String get detailLevelSimple => '간단';

  @override
  String get detailLevelBasic => '기본';

  @override
  String get detailLevelDetailed => '자세히';

  @override
  String get candidateEdited => '직접 고침';

  @override
  String reviewDuplicates(int count) {
    return '이미 있는 카드 $count개';
  }

  @override
  String get includeCard => '포함';

  @override
  String get duplicateSkip => '건너뛰기';

  @override
  String get duplicateMergeBack => '뒷면 합치기';

  @override
  String get duplicateAddNew => '새 카드로 추가';

  @override
  String get retake => '다시 찍기';

  @override
  String get retry => '다시 시도';

  @override
  String addCards(int count) {
    return '카드 $count개 추가';
  }

  @override
  String get extractionOffline => '인터넷에 연결되지 않았어요. 연결을 확인하고 다시 시도해 주세요.';

  @override
  String get photoRefused => '이 사진은 보낼 수 없어요. 다시 찍거나 다른 사진을 골라 주세요.';

  @override
  String get noCardsFound => '카드를 찾지 못했어요. 더 밝고 반듯하게 찍어 보세요.';

  @override
  String get dailyLimitReached => '오늘은 사진으로 카드를 더 만들 수 없어요. 내일 다시 시도해 주세요.';

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
  String get browse => '둘러보기';

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
  String get importToMyDecks => '내 덱으로 가져오기';

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
  String get importAsNewDeck => '새 덱으로';

  @override
  String get importIntoExistingDeck => '기존 덱에 추가';

  @override
  String importNewDeckHint(String name) {
    return '\"$name\" 덱을 새로 만들어 모든 카드를 가져와요.';
  }

  @override
  String get importTargetDeck => '덱';

  @override
  String get importDuplicates => '이미 있는 카드는';

  @override
  String get importConfirm => '가져오기';

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
  String get todayCountUnit => '장';

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
  String statCards(int count) {
    return '카드 $count';
  }

  @override
  String statReview(int count) {
    return '복습 $count';
  }

  @override
  String statNew(int count) {
    return '새 카드 $count';
  }

  @override
  String get swipeDontKnowHint => '모른다';

  @override
  String get swipeKnowHint => '안다';

  @override
  String get nextReviewToday => '다음 복습은 오늘이에요. 잊을 때쯤 다시 보여 드릴게요.';

  @override
  String get nextReviewTomorrow => '다음 복습은 내일이에요. 잊을 때쯤 다시 보여 드릴게요.';

  @override
  String nextReviewInDays(int days) {
    return '다음 복습은 $days일 뒤예요. 잊을 때쯤 다시 보여 드릴게요.';
  }

  @override
  String get summaryStudied => '학습한 카드';

  @override
  String get timeSpentLabel => '걸린 시간';

  @override
  String timeSpentValue(int minutes, int seconds) {
    return '$minutes분 $seconds초';
  }

  @override
  String get backToDecks => '덱으로 돌아가기';

  @override
  String consentNotice(String terms, String privacy) {
    return '계속하면 $terms과 $privacy에 동의하는 것으로 봐요.';
  }

  @override
  String get termsOfService => '이용약관';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get comingSoonBody => '아직 준비 중이에요. 곧 열어 드릴게요.';

  @override
  String get linkNotOpened => '링크를 열지 못했어요. 다시 시도해 주세요.';

  @override
  String appVersion(String version) {
    return '버전 $version';
  }
}
