import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'failure.dart';
import 'model.dart';
import 'server.dart';

/// The `media` table, through PostgREST, and the private `media` bucket,
/// through Supabase Storage, with the session the `account` domain signed
/// in. Each file lives at `{owner}/{media id}` (ADR 0107).
final class SupabaseMediaServer implements MediaServer {
  SupabaseMediaServer(
    this._client, {
    this.timeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;

  /// How long one request may take before it counts as failed.
  final Duration timeout;

  static const _bucket = 'media';

  @override
  Future<void> upload(MediaUpload upload, Uint8List bytes) =>
      _request(() async {
        final owner = _owner();
        await _client.from('media').upsert({
          'id': upload.id.value,
          'user_id': owner,
          'kind': upload.kind.key,
          'mime_type': upload.mimeType,
          'byte_size': upload.byteSize,
          'sha256': upload.sha256,
          'created_at': upload.createdAt.toUtc().toIso8601String(),
        }, ignoreDuplicates: true);
        try {
          await _client.storage
              .from(_bucket)
              .uploadBinary(
                _path(owner, upload.id),
                bytes,
                fileOptions: FileOptions(contentType: upload.mimeType),
              );
        } on StorageException catch (error) {
          if (!_isDuplicate(error)) rethrow;
        }
      });

  @override
  Future<Uint8List?> download(MediaId id) => _request(() async {
    final owner = _owner();
    try {
      return await _client.storage.from(_bucket).download(_path(owner, id));
    } on StorageException catch (error) {
      if (_isNotFound(error)) return null;
      rethrow;
    }
  });

  @override
  Future<void> delete(MediaId id) => _request(() async {
    final owner = _owner();
    await _client.storage.from(_bucket).remove([_path(owner, id)]);
    await _client.from('media').delete().eq('id', id.value);
  });

  String _owner() => switch (_client.auth.currentUser) {
    final user? => user.id,
    null => throw const MediaTransferFailed('no account is signed in'),
  };

  static String _path(String owner, MediaId id) => '$owner/${id.value}';

  static bool _isDuplicate(StorageException error) => _status(error) == '409';

  static bool _isNotFound(StorageException error) => _status(error) == '404';

  /// The status Storage names in its answer's body, which it sends with an
  /// HTTP 400; a download leaves that body unparsed, as the message.
  static String? _status(StorageException error) {
    try {
      if (jsonDecode(error.message) case {'statusCode': final Object code}) {
        return '$code';
      }
    } on FormatException {
      // A message that is not JSON names no status of its own.
    }
    return error.statusCode;
  }

  Future<T> _request<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on MediaFailure {
      rethrow;
    } on Exception catch (cause) {
      // A timeout, a refused or failed PostgREST or Storage request, or the
      // HTTP client's own failure: each is retried on the next run.
      throw MediaTransferFailed(cause);
    }
  }
}
