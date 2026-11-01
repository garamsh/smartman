import 'dart:math';

/// Excel's built-in format ids SSF's table holds, with the date formats Korean
/// Excel draws differently, as ADR 0125 lists them. Any other id reads as
/// General.
final spreadsheetBuiltInFormats = <int, String>{
  0: 'General',
  1: '0',
  2: '0.00',
  3: '#,##0',
  4: '#,##0.00',
  9: '0%',
  10: '0.00%',
  11: '0.00E+00',
  12: '# ?/?',
  13: '# ??/??',
  14: 'yyyy-mm-dd',
  15: 'd-mmm-yy',
  16: 'd-mmm',
  17: 'mmm-yy',
  18: 'h:mm AM/PM',
  19: 'h:mm:ss AM/PM',
  20: 'h:mm',
  21: 'h:mm:ss',
  22: 'yyyy-mm-dd h:mm',
  for (final id in const [27, 28, 29, 30, 31, 34, 35, 36]) id: 'yyyy-mm-dd',
  37: '#,##0 ;(#,##0)',
  38: '#,##0 ;[Red](#,##0)',
  39: '#,##0.00;(#,##0.00)',
  40: '#,##0.00;[Red](#,##0.00)',
  45: 'mm:ss',
  46: '[h]:mm:ss',
  47: 'mmss.0',
  48: '##0.0E+0',
  49: '@',
  for (var id = 50; id <= 58; id++) id: 'yyyy-mm-dd',
};

/// A cell's number as the sheet shows it through its number format [code],
/// read as SSF 0.11.2 reads one (ADR 0142). A format that cannot be read
/// draws as General, as the web draws one SSF refuses.
String shownNumber(String code, double value, {required bool date1904}) {
  try {
    return _Drawing(value, date1904).ofCode(code);
  } on _Unreadable {
    return _general(value);
  }
}

/// A number format this reader cannot draw.
final class _Unreadable implements Exception {
  const _Unreadable();
}

const _days = [
  ('Sun', 'Sunday'),
  ('Mon', 'Monday'),
  ('Tue', 'Tuesday'),
  ('Wed', 'Wednesday'),
  ('Thu', 'Thursday'),
  ('Fri', 'Friday'),
  ('Sat', 'Saturday'),
];

const _months = [
  ('J', 'Jan', 'January'),
  ('F', 'Feb', 'February'),
  ('M', 'Mar', 'March'),
  ('A', 'Apr', 'April'),
  ('M', 'May', 'May'),
  ('J', 'Jun', 'June'),
  ('J', 'Jul', 'July'),
  ('A', 'Aug', 'August'),
  ('S', 'Sep', 'September'),
  ('O', 'Oct', 'October'),
  ('N', 'Nov', 'November'),
  ('D', 'Dec', 'December'),
];

/// The characters SSF draws as themselves outside quotes.
const _plainCharacters = r",$-+/():!^&'~{}<>=€acfijklopqrtuvwxzP";

const _numberCharacters = '0#?.,E+-%';

/// The number of log10 per natural log, Math.LOG10E.
const _log10e = 0.4342944819032518;

/// A part of a format: its kind, as SSF's tokens name them, and its text.
final class _Token {
  _Token(this.kind, this.text);

  String kind;
  String text;
}

/// A serial date's parts.
final class _Date {
  _Date(
    this.days,
    this.year,
    this.month,
    this.day,
    this.weekday,
    this.hours,
    this.minutes,
    this.seconds,
    this.fraction,
  );

  final int days;
  final int year;
  final int month;
  final int day;

  /// From 0, Sunday.
  final int weekday;
  int hours;
  int minutes;
  int seconds;
  double fraction;
}

bool _isGeneral(String text, [int at = 0]) =>
    text.length >= at + 7 &&
    text.substring(at, at + 7).toLowerCase() == 'general';

/// Draws one number, its date parts read once.
final class _Drawing {
  _Drawing(this.value, this.date1904);

  final double value;
  final bool date1904;

  String ofCode(String code) {
    if (_isGeneral(code)) return _general(value);
    final (section, count) = _section(code);
    if (_isGeneral(section)) return _general(value);
    return _evaluate(section, count);
  }

  /// The format's sections, split at each semicolon outside a quote.
  List<String> _split(String code) {
    final sections = <String>[];
    var quoted = false;
    var start = 0;
    for (var at = 0; at < code.length; at++) {
      switch (code[at]) {
        case '"':
          quoted = !quoted;
        case '_' || '*' || r'\':
          at++;
        case ';':
          sections.add(code.substring(start, at));
          start = at + 1;
      }
    }
    sections.add(code.substring(start));
    if (quoted) throw const _Unreadable();
    return sections;
  }

  /// The section [value] draws through, and how many sections number it.
  (String, int) _section(String code) {
    final sections = _split(code);
    if (sections.length > 4) throw const _Unreadable();
    final text = sections.last.contains('@');
    final count = sections.length < 4 && text
        ? sections.length - 1
        : sections.length;
    final four = switch (sections) {
      [final a] when text => ['General', 'General', 'General', a],
      [final a] => [a, a, a, '@'],
      [final a, final b] when text => [a, a, a, b],
      [final a, final b] => [a, b, a, '@'],
      [final a, final b, final c] when text => [a, b, a, c],
      [final a, final b, final c] => [a, b, c, '@'],
      _ => sections,
    };
    final chosen = value > 0
        ? four[0]
        : value < 0
        ? four[1]
        : four[2];
    final conditional = RegExp(r'\[[=<>]');
    if (!conditional.hasMatch(four[0]) && !conditional.hasMatch(four[1])) {
      return (chosen, count);
    }
    final condition = RegExp(r'\[(=|>[=]?|<[>=]?)(-?\d+(?:\.\d*)?)\]');
    final first = condition.firstMatch(four[0]);
    final second = condition.firstMatch(four[1]);
    if (_holds(first)) return (four[0], count);
    if (_holds(second)) return (four[1], count);
    return (four[first != null && second != null ? 2 : 1], count);
  }

  bool _holds(RegExpMatch? condition) {
    if (condition == null) return false;
    final limit = double.parse(condition[2]!);
    return switch (condition[1]) {
      '=' => value == limit,
      '>' => value > limit,
      '<' => value < limit,
      '<>' => value != limit,
      '>=' => value >= limit,
      '<=' => value <= limit,
      _ => false,
    };
  }

  /// The date [value] names, or null past Excel's range.
  _Date? _dateOf() {
    if (value > 2958465 || value < 0) return null;
    var date = value.toInt();
    var whole = date;
    var time = (86400 * (value - date)).floor();
    var fraction = 86400 * (value - date) - time;
    if (fraction.abs() < 1e-6) fraction = 0;
    if (date1904) date += 1462;
    if (fraction > 0.9999) {
      fraction = 0;
      if (++time == 86400) {
        time = 0;
        date++;
        whole++;
      }
    }
    final int year, month, day, weekday;
    if (date == 60) {
      (year, month, day, weekday) = (1900, 2, 29, 3);
    } else if (date == 0) {
      (year, month, day, weekday) = (1900, 1, 0, 6);
    } else {
      // Excel counts 29 February 1900, a day that never was.
      final counted = date > 60 ? date - 1 : date;
      final parts = DateTime.utc(1900, 1, counted);
      (year, month, day) = (parts.year, parts.month, parts.day);
      final sunday = parts.weekday % 7;
      weekday = counted < 60 ? (sunday + 6) % 7 : sunday;
    }
    return _Date(
      whole,
      year,
      month,
      day,
      weekday,
      time ~/ 3600,
      time ~/ 60 % 60,
      time % 60,
      fraction,
    );
  }

  String _evaluate(String format, int count) {
    final tokens = <_Token>[];
    _Date? date;
    var last = 't';
    var hours = 'H';
    var at = 0;

    /// Moves past the run of characters [matches] takes, from [at], and
    /// returns the run with the character at [at].
    String run(bool Function(String) matches) {
      final start = at;
      at++;
      while (at < format.length && matches(format[at])) {
        at++;
      }
      return format.substring(start, at);
    }

    while (at < format.length) {
      final character = format[at];
      switch (character) {
        case 'G':
          if (!_isGeneral(format, at)) throw const _Unreadable();
          tokens.add(_Token('t', _general(value)));
          at += 7;
        case '"':
          final end = format.indexOf('"', at + 1);
          tokens.add(_Token('t', format.substring(at + 1, end)));
          at = end + 1;
        case r'\':
          at++;
          if (at >= format.length) throw const _Unreadable();
          tokens.add(_Token('t', format[at]));
          at++;
        case '_':
          tokens.add(_Token('t', ' '));
          at += 2;
        case '@':
          tokens.add(_Token('t', _plainNumber(value)));
          at++;
        case 'B' || 'b'
            when at + 1 < format.length && '12'.contains(format[at + 1]):
          // SSF's calendars, which no word list holds.
          throw const _Unreadable();
        case 'B' ||
            'b' ||
            'M' ||
            'D' ||
            'Y' ||
            'H' ||
            'S' ||
            'E' ||
            'm' ||
            'd' ||
            'y' ||
            'h' ||
            's' ||
            'e' ||
            'g':
          if (value < 0) return '';
          date ??= _dateOf();
          if (date == null) return '';
          final lower = character.toLowerCase();
          final text = run((next) => next.toLowerCase() == lower);
          final kind = switch (lower) {
            'm' when last.toLowerCase() == 'h' => 'M',
            'h' => hours,
            _ => lower,
          };
          tokens.add(_Token(kind, lower * text.length));
          last = kind;
        case 'A' || 'a' || '上':
          date ??= _dateOf();
          final rest = format.substring(at).toUpperCase();
          final marks = rest.startsWith('A/P')
              ? ('A', 'P', 3)
              : rest.startsWith('AM/PM')
              ? ('AM', 'PM', 5)
              : rest.startsWith('上午/下午')
              ? ('上午', '下午', 5)
              : null;
          if (marks == null) {
            tokens.add(_Token('t', character));
            at++;
          } else {
            if (date == null) return '';
            tokens.add(_Token('t', date.hours >= 12 ? marks.$2 : marks.$1));
            hours = 'h';
            at += marks.$3;
          }
          last = character;
        case '[':
          final end = format.indexOf(']', at);
          if (end < 0) throw const _Unreadable();
          final text = format.substring(at, end + 1);
          at = end + 1;
          if (RegExp(r'^\[[HhMmSsชนท]*\]$').hasMatch(text)) {
            date ??= _dateOf();
            if (date == null) return '';
            tokens.add(_Token('Z', text.toLowerCase()));
            last = text[1];
          } else if (text.contains(r'$')) {
            final symbol = RegExp(r'\$([^-\[\]]*)').firstMatch(text)?[1];
            tokens.add(
              _Token('c', symbol == null || symbol.isEmpty ? r'$' : symbol),
            );
          }
        case '.' when date != null:
          tokens.add(_Token('s', run((next) => next == '0')));
        case '.' || '0' || '#':
          tokens.add(_Token('n', run(_numberCharacters.contains)));
        case '?':
          tokens.add(_Token('?', run((next) => next == '?')));
          last = '?';
        case '*':
          at++;
          if (at < format.length && (format[at] == ' ' || format[at] == '*')) {
            at++;
          }
        case '(' || ')' || ' ' || r'$':
          tokens.add(_Token('t', character));
          at++;
        case '1' || '2' || '3' || '4' || '5' || '6' || '7' || '8' || '9':
          tokens.add(_Token('D', run('0123456789'.contains)));
        default:
          if (!_plainCharacters.contains(character)) {
            throw const _Unreadable();
          }
          tokens.add(_Token('t', character));
          at++;
      }
    }
    for (final token in tokens.where((token) => token.kind == 'c')) {
      // A locale tag on a date draws nothing; on a number, its symbol.
      token.kind = 't';
      if (date != null) token.text = '';
    }
    if (date != null) _fillDate(tokens, date, hours);
    return _fillNumber(tokens, count);
  }

  /// Reads which parts are hours and minutes, carries a rounded second into
  /// them, and writes each date part.
  void _fillDate(List<_Token> tokens, _Date date, String hours) {
    var last = 't';
    var precision = 0;
    var decimals = 0;
    for (final token in tokens.reversed) {
      switch (token.kind) {
        case 'h' || 'H':
          token.kind = hours;
          last = 'h';
          precision = max(precision, 1);
        case 's':
          final tail = RegExp(r'\.0+$').firstMatch(token.text);
          if (tail != null) decimals = max(decimals, tail[0]!.length - 1);
          precision = max(precision, 3);
          last = 's';
        case 'd' || 'y' || 'M' || 'e':
          last = token.kind;
        case 'm' when last == 's':
          token.kind = 'M';
          precision = max(precision, 2);
        case 'Z':
          if (token.text.contains('h')) precision = max(precision, 1);
          if (token.text.contains('m')) precision = max(precision, 2);
          if (token.text.contains('s')) precision = max(precision, 3);
      }
    }
    if (precision == 1 || precision == 2) {
      if (date.fraction >= 0.5) {
        date.fraction = 0;
        date.seconds++;
      }
      if (date.seconds >= 60) {
        date.seconds = 0;
        date.minutes++;
      }
      if (precision == 1 && date.minutes >= 60) {
        date.minutes = 0;
        date.hours++;
      }
    }
    for (final token in tokens) {
      if (const {
        'd',
        'm',
        'y',
        'h',
        'H',
        'M',
        's',
        'e',
        'Z',
        'b',
      }.contains(token.kind)) {
        token.text = _datePart(token.kind, token.text, date, decimals);
        token.kind = 't';
      }
    }
  }

  String _datePart(String kind, String format, _Date date, int decimals) {
    String padded(int value, int width) => value.toString().padLeft(width, '0');
    final short = format.length <= 2;
    String clock(int value) =>
        short ? padded(value, format.length) : throw const _Unreadable();
    switch (kind) {
      case 'b' || 'y':
        final year = kind == 'b' ? date.year + 543 : date.year;
        return short ? padded(year % 100, 2) : padded(year % 10000, 4);
      case 'm':
        final month = _months[date.month - 1];
        return switch (format.length) {
          1 || 2 => padded(date.month, format.length),
          3 => month.$2,
          5 => month.$1,
          _ => month.$3,
        };
      case 'd':
        final day = _days[date.weekday];
        return switch (format.length) {
          1 || 2 => padded(date.day, format.length),
          3 => day.$1,
          _ => day.$2,
        };
      case 'h':
        return clock(1 + (date.hours + 11) % 12);
      case 'H':
        return clock(date.hours);
      case 'M':
        return clock(date.minutes);
      case 's':
        return _seconds(format, date, decimals);
      case 'Z':
        final hours = date.days * 24 + date.hours;
        final minutes = hours * 60 + date.minutes;
        final total = switch (format) {
          '[h]' || '[hh]' => hours,
          '[m]' || '[mm]' => minutes,
          '[s]' ||
          '[ss]' => minutes * 60 + (date.seconds + date.fraction).round(),
          _ => throw const _Unreadable(),
        };
        return padded(total, format.length == 3 ? 1 : 2);
      case 'e':
        return date.year.toString();
    }
    throw const _Unreadable();
  }

  String _seconds(String format, _Date date, int decimals) {
    if (!const {'s', 'ss', '.0', '.00', '.000'}.contains(format)) {
      throw const _Unreadable();
    }
    if (date.fraction == 0 && format[0] == 's') {
      return date.seconds.toString().padLeft(format.length, '0');
    }
    final scale = decimals >= 2
        ? (decimals == 3 ? 1000 : 100)
        : (decimals == 1 ? 10 : 1);
    var scaled = (scale * (date.seconds + date.fraction)).round();
    if (scaled >= 60 * scale) scaled = 0;
    if (format == 's') {
      return scaled == 0 ? '0' : _plainNumber(scaled / scale);
    }
    final text = scaled.toString().padLeft(2 + decimals, '0');
    if (format == 'ss') return text.substring(0, 2);
    return '.${text.substring(2, min(text.length, 1 + format.length))}';
  }

  /// Writes the number through the format's number parts, and joins it.
  String _fillNumber(List<_Token> tokens, int count) {
    bool isNumber(_Token token) => token.kind == 'n' || token.kind == '?';
    String joined(Iterable<_Token> part) =>
        part.map((token) => token.text).join();
    final first = tokens.indexWhere(isNumber);
    if (first < 0) return joined(tokens);
    final last = tokens.lastIndexWhere(isNumber);
    var end = last + 1;
    // A fixed denominator follows the last number part: `/`, then its digits.
    if (end + 1 < tokens.length &&
        tokens[end].text == '/' &&
        tokens[end + 1].kind == 'D') {
      end += 2;
    }
    final span = tokens.sublist(first, end);
    final core = joined(span);
    final drawn = value < 0 && count > 1 ? -value : value;
    final sign = drawn < 0 ? '-' : '';
    final magnitude = drawn.abs();
    if (magnitude >= 1e21) throw const _Unreadable();
    final before = joined(tokens.take(first));
    final after = joined(tokens.skip(end));
    if (core.contains('/')) {
      return '$sign$before${_fraction(core, magnitude)}$after';
    }
    if (span.length == 1 && core.contains('E')) {
      return '$before${_exponent(core, drawn)}$after';
    }
    return '$sign$before${_digits(span, magnitude)}$after';
  }

  /// [magnitude] through the number parts in [span], the rest of it literal.
  String _digits(List<_Token> span, double magnitude) {
    // One entry a character: a number part's, or a literal's whole text.
    final slots = <String>[
      for (final token in span)
        if (token.kind == 'n' || token.kind == '?')
          ...token.text.split('')
        else
          token.text,
    ];
    const placeholders = {'0', '#', '?'};
    final point = slots.indexOf('.');
    final whole = point < 0 ? slots.length : point;
    var scaled = magnitude;
    for (final slot in slots) {
      if (slot == '%') scaled *= 100;
    }
    // Commas right after the last placeholder scale by a thousand each.
    for (final end in [whole, slots.length]) {
      for (var at = end - 1; at >= 0 && slots[at] == ','; at--) {
        scaled /= 1000;
        slots[at] = '';
      }
    }
    final grouped = slots.take(whole).contains(',');
    final decimals = point < 0
        ? 0
        : slots.skip(point + 1).where(placeholders.contains).length;
    final (integer, fraction) = _rounded(scaled, decimals);
    final out = List<String>.filled(slots.length, '');
    var digit = integer.length;
    var written = 0;
    String grouping(String text) {
      final mark = grouped && written > 0 && written % 3 == 0 ? ',' : '';
      written++;
      return '$text$mark';
    }

    var leftmost = -1;
    for (var at = whole - 1; at >= 0; at--) {
      final slot = slots[at];
      if (slot == ',') continue;
      if (!placeholders.contains(slot)) {
        out[at] = slot;
        continue;
      }
      leftmost = at;
      if (digit > 0) {
        out[at] = grouping(integer[--digit]);
      } else if (slot != '#') {
        out[at] = grouping(slot == '0' ? '0' : ' ');
      }
    }
    while (digit > 0 && leftmost >= 0) {
      out[leftmost] = '${grouping(integer[--digit])}${out[leftmost]}';
    }
    if (point >= 0) {
      // With no placeholder before the point, the integer's digits go there.
      out[point] = '${leftmost < 0 ? integer : ''}.';
      final kept = fraction.replaceFirst(RegExp(r'0+$'), '').length;
      var index = 0;
      for (var at = point + 1; at < slots.length; at++) {
        final slot = slots[at];
        if (!placeholders.contains(slot)) {
          out[at] = slot;
          continue;
        }
        final digitAt = index++;
        if (digitAt < kept || slot == '0') {
          out[at] = fraction[digitAt];
        } else if (slot == '?') {
          out[at] = ' ';
        }
      }
    }
    return out.join();
  }

  /// [magnitude] rounded half up at [decimals], as its integer digits, none
  /// for zero, and its decimals.
  (String, String) _rounded(double magnitude, int decimals) {
    final scaled = magnitude * pow(10, decimals);
    final text = scaled < 9e15
        ? scaled.round().toString().padLeft(decimals + 1, '0')
        : magnitude.toStringAsFixed(decimals).replaceFirst('.', '');
    final split = text.length - decimals;
    final integer = text.substring(0, split);
    return (integer == '0' ? '' : integer, text.substring(split));
  }

  String _exponent(String format, double value) {
    final digits = format.indexOf('E') - format.indexOf('.') - 1;
    String text;
    if (RegExp(r'^#+0.0E\+0$').hasMatch(format)) {
      if (value == 0) return '0.0E+0';
      if (value < 0) return '-${_exponent(format, -value)}';
      text = _engineering(format, value, digits);
    } else {
      text = value.toStringAsExponential(digits);
    }
    if (format.endsWith('E+00') && RegExp(r'e[+-]\d$').hasMatch(text)) {
      final end = text.length - 1;
      text = '${text.substring(0, end)}0${text[end]}';
    }
    if (format.contains('E-')) text = text.replaceFirst('e+', 'e');
    return text.replaceFirst('e', 'E');
  }

  /// [value] with its exponent a multiple of the integer placeholders.
  String _engineering(String format, double value, int digits) {
    final period = format.indexOf('.');
    final magnitude = (log(value) * _log10e).floor();
    final shift = magnitude % period;
    final kept = (period + shift) % period;
    var text = (value / pow(10, shift)).toStringAsPrecision(digits + 1 + kept);
    if (!text.contains('e')) {
      text = text.contains('.')
          ? '${text}E+${magnitude - shift}'
          : '${text[0]}.${text.substring(1)}'
                'E+${magnitude - text.length + shift}';
      while (text.startsWith('0.')) {
        final cut = min(text.length, 2 + period);
        text = '${text[0]}${text.substring(2, cut)}.${text.substring(cut)}'
            .replaceFirstMapped(RegExp(r'^0+([1-9])'), (match) => match[1]!)
            .replaceFirst(RegExp(r'^0+\.'), '0.');
      }
      text = text.replaceFirst('+-', '-');
    }
    return text.replaceFirstMapped(RegExp(r'^([+-]?)(\d*)\.(\d*)[Ee]'), (
      match,
    ) {
      final tail = match[3]!;
      return '${match[1]}${match[2]}'
          '${tail.substring(0, min(kept, tail.length))}'
          '.${tail.substring(min(shift, tail.length))}E';
    });
  }

  String _fraction(String format, double magnitude) {
    if (RegExp(r'# (\?+)( ?)/( ?)(\d+)').firstMatch(format) case final fixed?) {
      final denominator = int.parse(fixed[4]!);
      final rounded = (magnitude * denominator).round();
      final whole = rounded ~/ denominator;
      final numerator = rounded - whole * denominator;
      final width = fixed[1]!.length;
      final digits = fixed[4]!.length;
      final part = numerator == 0
          ? ' ' * (width + 1 + digits)
          : '${numerator.toString().padLeft(width)}${fixed[2]}/${fixed[3]}'
                '${denominator.toString().padLeft(digits, '0')}';
      return '${whole == 0 ? '' : whole} $part';
    }
    final improper = RegExp(r'^([#0?]+)( ?)/( ?)([#0?]+)').firstMatch(format);
    if (improper != null) {
      final width = min(improper[4]!.length, 7);
      final (_, numerator, denominator) = _ratio(
        magnitude,
        pow(10, width).toInt() - 1,
        mixed: false,
      );
      final top = _integerIn(improper[1]!, numerator);
      final written = top.endsWith(' ')
          ? '${top.substring(0, top.length - 1)}0'
          : top;
      return '$written${improper[2]}/${improper[3]}'
          '${denominator.toString().padRight(width)}';
    }
    final mixed = RegExp(r'^# ([#0?]+)( ?)/( ?)([#0?]+)').firstMatch(format);
    if (mixed == null) throw const _Unreadable();
    final width = min(max(mixed[1]!.length, mixed[4]!.length), 7);
    final (whole, numerator, denominator) = _ratio(
      magnitude,
      pow(10, width).toInt() - 1,
      mixed: true,
    );
    final lead = whole != 0
        ? '$whole'
        : numerator != 0
        ? ''
        : '0';
    final part = numerator != 0
        ? '${numerator.toString().padLeft(width)}${mixed[2]}/${mixed[3]}'
              '${denominator.toString().padRight(width)}'
        : ' ' * (2 * width + 1 + mixed[2]!.length + mixed[3]!.length);
    return '$lead $part';
  }

  /// [number] written in the integer placeholders of [format].
  String _integerIn(String format, int number) {
    final text = number == 0 && !format.contains('0') ? '' : '$number';
    if (text.length >= format.length) return text;
    final pad = format
        .substring(0, format.length - text.length)
        .replaceAll('#', '')
        .replaceAll('?', ' ');
    return '$pad$text';
  }

  /// [number] as a continued fraction with a denominator up to [limit]: a
  /// whole part where [mixed], a numerator and a denominator.
  (int, int, int) _ratio(double number, int limit, {required bool mixed}) {
    var rest = number;
    var (p2, p1, p) = (0, 1, 0);
    var (q2, q1, q) = (1, 0, 0);
    while (q1 < limit) {
      final whole = rest.floor();
      p = whole * p1 + p2;
      q = whole * q1 + q2;
      if (rest - whole < 0.00000005) break;
      rest = 1 / (rest - whole);
      (p2, p1) = (p1, p);
      (q2, q1) = (q1, q);
    }
    if (q > limit) {
      (p, q) = q1 > limit ? (p2, q2) : (p1, q1);
    }
    if (!mixed) return (0, p, q);
    final integer = (p / q).floor();
    return (integer, p - integer * q, q);
  }
}

/// [value] as JavaScript writes a number: a whole one with no decimals.
String _plainNumber(double value) =>
    value == value.truncateToDouble() && value.abs() < 1e21
    ? value.toStringAsFixed(0)
    : value.toString();

/// [value] in Excel's General format: up to eleven characters of it.
String _general(double value) {
  if (value == value.truncateToDouble() &&
      value >= -2147483648 &&
      value < 2147483648) {
    return value.toInt().toString();
  }
  final magnitude = (log(value.abs()) * _log10e).floor();
  final String text;
  if (magnitude >= -4 && magnitude <= -1) {
    text = value.toStringAsPrecision(10 + magnitude);
  } else if (magnitude.abs() <= 9) {
    text = _generalSmall(value);
  } else if (magnitude == 10) {
    final fixed = value.toStringAsFixed(10);
    text = fixed.substring(0, min(12, fixed.length));
  } else {
    final fixed = _stripDecimal(value.toStringAsFixed(11));
    text = fixed.length > (value < 0 ? 12 : 11) || fixed == '0' || fixed == '-0'
        ? value.toStringAsPrecision(6)
        : fixed;
  }
  return _stripDecimal(_normalizeExponent(text.toUpperCase()));
}

String _generalSmall(double value) {
  final width = value < 0 ? 12 : 11;
  final fixed = _stripDecimal(value.toStringAsFixed(12));
  if (fixed.length <= width) return fixed;
  final precise = value.toStringAsPrecision(10);
  if (precise.length <= width) return precise;
  return value.toStringAsExponential(5);
}

String _stripDecimal(String text) => text.contains('.')
    ? text.replaceFirstMapped(
        RegExp(r'(?:\.0*|(\.\d*[1-9])0+)$'),
        (match) => match[1] ?? '',
      )
    : text;

String _normalizeExponent(String text) => text.contains('E')
    ? text
          .replaceFirstMapped(
            RegExp(r'(?:\.0*|(\.\d*[1-9])0+)[Ee]'),
            (match) => '${match[1] ?? ''}E',
          )
          .replaceFirstMapped(
            RegExp(r'(E[+-])(\d)$'),
            (match) => '${match[1]}0${match[2]}',
          )
    : text;
