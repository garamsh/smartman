import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartman/media/media.dart';
import 'package:smartman/media/src/model.dart' show MediaKind;
import 'package:supabase_flutter/supabase_flutter.dart';

const _owner = '00000000-0000-4000-8000-00000000000a';
const _id = MediaId('0199f3b2-7c1e-7a00-8000-000000000001');

/// An unsigned token for [_owner] that expires in a day, which the client
/// reads without asking the server.
String _token() {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(days: 1));
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _owner, 'role': 'authenticated', 'exp': exp.millisecondsSinceEpoch ~/ 1000})}.'
      'signature';
}

/// A client signed in as [_owner] whose every request [answer] answers,
/// recorded in [requests].
Future<SupabaseClient> _client(
  List<http.Request> requests,
  http.Response Function(http.Request request) answer,
) async {
  final client = SupabaseClient(
    'https://example.test',
    'anon-key',
    httpClient: MockClient((request) async {
      requests.add(request);
      return answer(request);
    }),
  );
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': _token(),
      'token_type': 'bearer',
      'expires_in': 86400,
      'refresh_token': 'refresh',
      'user': {
        'id': _owner,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-10-01T00:00:00Z',
      },
    }),
  );
  return client;
}

final _upload = MediaUpload(
  id: _id,
  kind: MediaKind.image,
  mimeType: 'image/jpeg',
  byteSize: 3,
  sha256: 'a' * 64,
  createdAt: DateTime.utc(2026, 10, 26),
);

void main() {
  test('an upload stores the row as the owner, then the file at {owner}/{media id}', () async {
    final requests = <http.Request>[];
    final client = await _client(
      requests,
      (request) => http.Response('{"Key":"media/x"}', 200, request: request),
    );
    addTearDown(client.dispose);

    await SupabaseMediaServer(client)
        .upload(_upload, Uint8List.fromList([1, 2, 3]));

    expect(requests, hasLength(2));
    final row = requests.first;
    expect(row.url.path, '/rest/v1/media');
    expect(row.headers['Prefer'], contains('resolution=ignore-duplicates'));
    expect(
      row.url.queryParameters['on_conflict'],
      'user_id,id',
      reason: 'only the owner\'s own row under the id counts as stored',
    );
    expect(jsonDecode(row.body), {
      'id': _id.value,
      'user_id': _owner,
      'kind': 'image',
      'mime_type': 'image/jpeg',
      'byte_size': 3,
      'sha256': 'a' * 64,
      'created_at': '2026-10-26T00:00:00.000Z',
    });
    final file = requests.last;
    expect(file.url.path, '/storage/v1/object/media/$_owner/${_id.value}');
    expect(file.method, 'POST', reason: 'a new file, never an overwrite');
    expect(file.headers['x-upsert'], 'false');
  });

  test('a file Storage already holds counts as uploaded, where another refusal fails the upload', () async {
    for (final (status, body, uploaded) in [
      (
        400,
        '{"statusCode":"409","error":"Duplicate","message":"exists"}',
        true,
      ),
      (
        403,
        '{"statusCode":"403","error":"Unauthorized","message":"no"}',
        false,
      ),
    ]) {
      final client = await _client(
        [],
        (request) => request.url.path.startsWith('/storage/')
            ? http.Response(body, status, request: request)
            : http.Response('', 201, request: request),
      );
      addTearDown(client.dispose);
      final upload = SupabaseMediaServer(client)
          .upload(_upload, Uint8List.fromList([1]));
      if (uploaded) {
        await expectLater(upload, completes);
      } else {
        await expectLater(upload, throwsA(isA<MediaTransferFailed>()));
      }
    }
  });

  test('a download of a file Storage does not hold is null, and of one it holds its bytes', () async {
    final missing = await _client(
      [],
      (request) => http.Response(
        '{"statusCode":"404","error":"not_found","message":"Object not found"}',
        400,
        request: request,
      ),
    );
    addTearDown(missing.dispose);
    expect(await SupabaseMediaServer(missing).download(_id), isNull);

    final requests = <http.Request>[];
    final held = await _client(
      requests,
      (request) => http.Response.bytes([7, 8], 200, request: request),
    );
    addTearDown(held.dispose);
    expect(await SupabaseMediaServer(held).download(_id), [7, 8]);
    expect(
      requests.single.url.path,
      '/storage/v1/object/media/$_owner/${_id.value}',
    );
  });

  test('a delete removes the file, then the row', () async {
    final requests = <http.Request>[];
    final client = await _client(
      requests,
      (request) => http.Response('[]', 200, request: request),
    );
    addTearDown(client.dispose);

    await SupabaseMediaServer(client).delete(_id);

    expect(requests.map((request) => (request.method, request.url.path)), [
      ('DELETE', '/storage/v1/object/media'),
      ('DELETE', '/rest/v1/media'),
    ]);
    expect(jsonDecode(requests.first.body), {
      'prefixes': ['$_owner/${_id.value}'],
    });
    expect(requests.last.url.queryParameters['id'], 'eq.${_id.value}');
    expect(requests.last.url.queryParameters['user_id'], 'eq.$_owner');
  });

  test('an unreachable server fails a transfer as one to retry', () async {
    final client = await _client(
      [],
      (request) => throw http.ClientException('no route to host'),
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseMediaServer(client).download(_id),
      throwsA(isA<MediaTransferFailed>()),
    );
  });
}
