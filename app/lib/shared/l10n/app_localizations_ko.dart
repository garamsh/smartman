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
}
