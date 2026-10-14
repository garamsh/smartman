import 'dart:convert';

import 'package:http/http.dart' as http;

import 'failure.dart';
import 'photo.dart';

/// A card the model read off the page, before the user reviews it.
final class CandidateCard {
  const CandidateCard({required this.front, required this.back});

  final String front;
  final String back;
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
    return [
      for (final card in cards)
        switch (card) {
          {'front': final String front, 'back': final String back}
              when front.trim().isNotEmpty && back.trim().isNotEmpty =>
            CandidateCard(front: front.trim(), back: back.trim()),
          _ => throw const ServiceFailed('a card is not two non-empty sides'),
        },
    ];
  }
  throw const ServiceFailed('the success body holds no card list');
}
