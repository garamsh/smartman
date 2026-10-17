import 'package:flutter/widgets.dart';

/// [text] with a word joiner between the characters of each word, so a line
/// breaks only at a space: Flutter otherwise breaks Korean between any two
/// syllables, which can leave one alone on a line.
String keepWords(String text) =>
    text.split(' ').map((word) => word.characters.join('⁠')).join(' ');
