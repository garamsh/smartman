import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';

void main() {
  group('CardKey.fromFront', () {
    test('applies NFKC, so compatibility forms match their plain form', () {
      expect(CardKey.fromFront('ｈｅｌｌｏ').value, 'hello');
      expect(CardKey.fromFront('ﬁne').value, 'fine');
      expect(CardKey.fromFront('café').value, 'café');
    });

    test('trims leading and trailing whitespace', () {
      expect(CardKey.fromFront('  hello\t\n').value, 'hello');
    });

    test('collapses a run of whitespace into one space', () {
      expect(CardKey.fromFront('good \t\n  morning').value, 'good morning');
    });

    test('case-folds', () {
      expect(CardKey.fromFront('HeLLo ΣΟΦΟΣ').value, 'hello σοφοσ');
    });

    test('keeps punctuation and accents', () {
      expect(CardKey.fromFront("Où est-il? L'été!").value, "où est-il? l'été!");
      expect(
        CardKey.fromFront('café').value,
        isNot(CardKey.fromFront('cafe').value),
      );
    });
  });
}
