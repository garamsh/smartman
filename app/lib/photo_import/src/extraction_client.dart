import 'dart:convert';

import 'package:http/http.dart' as http;

import 'detail_step.dart';
import 'failure.dart';
import 'photo.dart';

/// What a candidate was read from: an entry of a vocabulary page, or a point
/// of notes.
enum CandidateKind { vocabulary, note }

/// A card the model read off the page, before the user reviews it: its
/// headword or question, its fullest answer and a shorter form, the step from
/// which it is offered, and the part of speech and examples the page prints.
final class CandidateCard {
  const CandidateCard({
    required this.front,
    required this.answer,
    String? short,
    this.kind = CandidateKind.vocabulary,
    this.step = DetailStep.core,
    this.partOfSpeech,
    this.examples = const [],
  }) : short = short ?? answer;

  final CandidateKind kind;
  final String front;

  /// The fullest answer the page supports.
  final String answer;

  /// A shorter form of [answer]; [answer] itself when none was given.
  final String short;

  /// The step from which the card is offered.
  final DetailStep step;

  /// The page's own notation, such as "[동]"; null when it prints none.
  final String? partOfSpeech;

  /// Empty when the page prints none.
  final List<String> examples;

  /// Whether the card is offered at [at]: from its own step upward.
  bool offeredAt(DetailStep at) => step.value <= at.value;

  /// The answer at [at]: the short form at 핵심, the answer at 요점, with the
  /// part of speech and a space before it from 기본, and each example on a
  /// line of its own from 자세히.
  String backAt(DetailStep at) {
    final basic = switch (partOfSpeech) {
      final partOfSpeech? => '$partOfSpeech $answer',
      null => answer,
    };
    return switch (at) {
      DetailStep.core => short,
      DetailStep.keyPoints => answer,
      DetailStep.basic => basic,
      DetailStep.detailed || DetailStep.full => [basic, ...examples].join('\n'),
    };
  }
}

/// Sends a photo to `extract-cards` and returns the cards it found.
abstract interface class ExtractionClient {
  /// The cards on [photo]'s page, or null once [cancel] completes before the
  /// answer arrives. Throws a [PhotoImportFailure] for each refusal.
  Future<List<CandidateCard>?> extract(
    JpegPhoto photo, {
    required Future<void> cancel,
  });
}

/// Calls the deployed function over HTTP with the signed-in user's token.
final class HttpExtractionClient implements ExtractionClient {
  HttpExtractionClient(
    this._http, {
    required this.functionUrl,
    required this.accessToken,
  });

  final http.Client _http;

  /// The function's URL, `<supabase url>/functions/v1/extract-cards`.
  final Uri functionUrl;

  /// The current session's access token, or null when signed out.
  final Future<String?> Function() accessToken;

  @override
  Future<List<CandidateCard>?> extract(
    JpegPhoto photo, {
    required Future<void> cancel,
  }) async {
    final token = await accessToken();
    if (token == null) throw const SignInRequired();
    final request = http.AbortableRequest(
      'POST',
      functionUrl,
      abortTrigger: cancel,
    );
    request.headers['authorization'] = 'Bearer $token';
    request.headers['content-type'] = 'application/json';
    request.body = jsonEncode({'image': base64Encode(photo.bytes)});
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on http.RequestAbortedException {
      return null;
    } on http.ClientException catch (cause) {
      throw ExtractionOffline(cause);
    }
    return parseExtraction(response.statusCode, response.body);
  }
}

/// The cards a `200` [body] holds, or the failure [status] means, per the
/// contract in `docs/architecture/ai-extraction.md`.
List<CandidateCard> parseExtraction(int status, String body) =>
    switch (status) {
      200 => _parseCards(body),
      401 => throw const SignInRequired(),
      413 || 415 => throw PhotoRefused(status),
      422 => throw const NoCardsFound(),
      429 => throw const DailyLimitReached(),
      502 => throw const ModelFailed(),
      _ => throw ServiceFailed('HTTP $status'),
    };

List<CandidateCard> _parseCards(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const ServiceFailed('the success body is not JSON');
  }
  if (decoded case {'cards': final List<Object?> cards} when cards.isNotEmpty) {
    return [for (final card in cards) _parseCard(card)];
  }
  throw const ServiceFailed('the success body holds no card list');
}

/// A card of non-empty `front` and `back`. With `kind`, as `extract-cards`
/// answers since prompt v3: its `kind`, `answer`, `short` and `step`, and the
/// optional `partOfSpeech` and `examples`. Without it, as a function deployed
/// before answers: a vocabulary card at step 1, its answer its `meaning` or,
/// before the fields, its `back`, which is also its short form.
CandidateCard _parseCard(Object? card) {
  if (card
      case final Map<String, Object?> fields &&
          {'front': final String front, 'back': final String back}
      when front.trim().isNotEmpty && back.trim().isNotEmpty) {
    final partOfSpeech = fields.containsKey('partOfSpeech')
        ? _text(fields['partOfSpeech'])
        : null;
    final examples = switch (fields['examples']) {
      null => const <String>[],
      final List<Object?> list => [for (final item in list) _text(item)],
      _ => throw const ServiceFailed('examples is not a list'),
    };
    if (!fields.containsKey('kind')) {
      return CandidateCard(
        front: front.trim(),
        answer: fields.containsKey('meaning')
            ? _text(fields['meaning'])
            : back.trim(),
        partOfSpeech: partOfSpeech,
        examples: examples,
      );
    }
    final kind = switch (fields['kind']) {
      'vocabulary' => CandidateKind.vocabulary,
      'note' => CandidateKind.note,
      _ => throw const ServiceFailed('a card has an unknown kind'),
    };
    final step = switch (fields['step']) {
      final int value when value >= 1 && value <= 5 =>
        DetailStep.values[value - 1],
      _ => throw const ServiceFailed('a card has no step from 1 to 5'),
    };
    return CandidateCard(
      kind: kind,
      front: front.trim(),
      answer: _text(fields['answer']),
      short: _text(fields['short']),
      step: step,
      partOfSpeech: partOfSpeech,
      examples: examples,
    );
  }
  throw const ServiceFailed('a card is not two non-empty sides');
}

String _text(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  _ => throw const ServiceFailed('a card field is not non-empty text'),
};

/// The URL of `extract-cards` for the project whose PostgREST URL is
/// [restUrl]. The Supabase client builds both as `<project url>/rest/v1` and
/// `<project url>/functions/v1`, so the suffix is swapped. Throws
/// [ArgumentError] for a URL without that suffix.
Uri extractCardsUrl(String restUrl) {
  const rest = '/rest/v1';
  if (!restUrl.endsWith(rest)) {
    throw ArgumentError.value(restUrl, 'restUrl', 'does not end in $rest');
  }
  final project = restUrl.substring(0, restUrl.length - rest.length);
  return Uri.parse('$project/functions/v1/extract-cards');
}
