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
  String get decksTitle => '덱';

  @override
  String get noDecks => '아직 덱이 없습니다. 새 덱을 만들어 시작하세요.';

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
      other: '카드 $count장도 함께 삭제됩니다.',
      zero: '이 덱에는 카드가 없습니다.',
    );
    return '$_temp0';
  }

  @override
  String get deckName => '이름';

  @override
  String get deckNameRequired => '이름을 입력하세요';

  @override
  String get noCards => '아직 카드가 없습니다. 카드를 추가해 시작하세요.';

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
  String get storageFailure => '기기 저장소를 읽거나 쓰지 못했습니다. 다시 시도해 주세요.';

  @override
  String get unreadableCard => '이 덱에 읽을 수 없는 카드가 있습니다.';

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
    return '$answered / $total';
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
  String get sessionSummaryTitle => '학습 끝';

  @override
  String get nothingToStudy => '지금 학습할 카드가 없습니다.';

  @override
  String cardsStudied(int count) {
    return '학습한 카드: $count장';
  }

  @override
  String knowCount(int count) {
    return '안다: $count번';
  }

  @override
  String dontKnowCount(int count) {
    return '모른다: $count번';
  }

  @override
  String timeSpent(int minutes, int seconds) {
    return '걸린 시간: $minutes분 $seconds초';
  }

  @override
  String get done => '완료';

  @override
  String get answerNotSaved => '답을 기기에 저장하지 못했습니다. 이 카드의 일정은 바뀌지 않았습니다.';

  @override
  String get schedulingFailure => '이 카드의 다음 복습 일정을 계산하지 못했습니다. 일정은 바뀌지 않았습니다.';

  @override
  String get account => '계정';

  @override
  String get accountTitle => '계정';

  @override
  String get welcomeBody => '밀어서 답하고, 잊을 때쯤 다시 보여 주는 암기 카드.';

  @override
  String get signInWithGoogle => 'Google로 로그인';

  @override
  String get signInWithAppleSoon => 'Apple로 로그인 (준비 중)';

  @override
  String get signingIn => '로그인 중';

  @override
  String signedInAs(String email) {
    return '$email 계정으로 로그인했습니다';
  }

  @override
  String get signedIn => '로그인했습니다';

  @override
  String get signOut => '로그아웃';

  @override
  String get signingOut => '로그아웃 중';

  @override
  String get accountOffline => '서버에 연결하지 못했습니다. 인터넷 연결을 확인해 주세요.';

  @override
  String get accountMisconfigured => '이 앱의 로그인 설정에 문제가 있어 로그인할 수 없습니다.';

  @override
  String get accountRejected => 'Google 로그인이 거부되었습니다. 다시 시도해 주세요.';

  @override
  String get displaySection => '화면';

  @override
  String get themeSystem => '시스템';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String todayBreakdown(int review, int fresh) {
    return '복습 $review · 새 카드 $fresh';
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
  String deckSummary(int cards, int review, int fresh) {
    return '카드 $cards장 · 오늘 복습 $review · 새 카드 $fresh';
  }

  @override
  String studyCount(int count) {
    return '학습 · $count장';
  }

  @override
  String get searchCards => '검색';

  @override
  String get noMatches => '찾는 카드가 없습니다. 다른 말로 검색해 보세요.';

  @override
  String get saveAndNext => '저장하고 다음 카드';

  @override
  String get deleteCardTitle => '이 카드를 삭제할까요?';

  @override
  String get deleteCardBody => '이 카드의 학습 기록도 함께 삭제됩니다.';

  @override
  String get unsyncedChangesTitle => '동기화되지 않은 변경이 있어요';

  @override
  String get unsyncedChangesBody => '로그아웃하면 이 기기에서 지워지고 다른 기기에서는 볼 수 없어요.';

  @override
  String get signOutAnyway => '그래도 로그아웃';

  @override
  String get dataNotCleared => '이 기기의 데이터를 지우지 못했어요. 다른 계정으로 로그인하면 지워져요.';

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
  String get noCardsFound => '카드를 찾지 못했어요. 더 밝고 반듯하게 찍어 보세요';

  @override
  String get dailyLimitReached => '오늘은 사진으로 카드를 더 만들 수 없어요. 내일 다시 시도해 주세요.';

  @override
  String get modelFailed => '카드를 읽지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get signInRequired => '로그인이 필요해요. 계정 화면에서 다시 로그인해 주세요.';

  @override
  String get serviceFailed => '지금은 사진으로 카드를 만들 수 없어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get photoUnreadable => '이 사진을 읽을 수 없어요. 다른 사진을 골라 주세요.';

  @override
  String get deckDeleted => '이 덱은 삭제됐어요. 다른 덱을 골라 주세요.';
}
