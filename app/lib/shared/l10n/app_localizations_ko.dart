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
  String get noDecks => '아직 덱이 없습니다';

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
  String get noCards => '아직 카드가 없습니다';

  @override
  String get newCard => '새 카드';

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
  String get saveCard => '카드 저장';

  @override
  String get duplicateTitle => '같은 앞면의 카드가 있습니다';

  @override
  String duplicateBody(String front) {
    return '이 덱에 앞면이 \"$front\"인 카드가 이미 있습니다.';
  }

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
  String get rename => '이름 바꾸기';

  @override
  String get delete => '삭제';

  @override
  String get study => '학습';

  @override
  String get know => '알아요';

  @override
  String get dontKnow => '몰라요';

  @override
  String get previousCard => '이전 카드';

  @override
  String get correctToDontKnow => '탭하면 \'몰라요\'로 고칩니다';

  @override
  String previousCardSemantics(String front, String back, String answer) {
    return '이전 카드. 앞면: $front. 뒷면: $back. 답: $answer';
  }

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
    return '알아요: $count번';
  }

  @override
  String dontKnowCount(int count) {
    return '몰라요: $count번';
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
}
