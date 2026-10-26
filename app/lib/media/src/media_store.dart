import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../database/database.dart';
import 'failure.dart';
import 'model.dart';
import 'server.dart';

/// The user's media on this device: each file kept in [directory] under its
/// id, the queue of files waiting to be uploaded and the queue of files the
/// user let go, waiting to be deleted from the server (ADR 0107).
///
/// A file is stored on the device first, so it shows at once; [drain] sends
/// both queues to the server and is run again after a failure.
class MediaStore {
  MediaStore(
    this._db,
    this._server, {
    required this.directory,
    required this._clock,
    required this._newId,
  });

  final AppDatabase _db;
  final MediaServer _server;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Where each file is kept, named by its id: the ones made here and the
  /// ones downloaded.
  final Directory directory;

  /// The downloads under way, so a file shown twice is fetched once.
  final _reads = <MediaId, Future<Uint8List?>>{};

  /// Keeps [image] on the device and queues it for upload; returns its id.
  Future<MediaId> addImage(PreparedImage image) =>
      _add(MediaKind.image, 'image/jpeg', image.bytes, image.sha256);

  /// Keeps [audio] on the device and queues it for upload; returns its id
  /// (ADR 0112).
  Future<MediaId> addAudio(PreparedAudio audio) =>
      _add(MediaKind.audio, audio.mimeType, audio.bytes, audio.sha256);

  /// How many times [fetchShared] asks for a file the network fails to
  /// bring.
  static const fetchAttempts = 3;

  /// How many files [fetchShared] reads at once.
  static const fetchesAtOnce = 4;

  /// The files of [ids] in [owner]'s folder, each copied onto the device
  /// under a new id as it arrives, so only the files in flight are held in
  /// memory, and not yet queued (ADR 0113). An id is absent when the server
  /// holds no file the user may read, its bytes are of no type the bucket
  /// takes, or the network fails [fetchAttempts] times.
  ///
  /// Each file returned is then queued by [addFetched] or deleted by
  /// [discardFetched].
  Future<Map<MediaId, FetchedMedia>> fetchShared(
    String owner,
    Iterable<MediaId> ids,
  ) async {
    final fetched = <MediaId, FetchedMedia>{};
    final pending = ids.toSet().toList();
    for (var start = 0; start < pending.length; start += fetchesAtOnce) {
      await Future.wait([
        for (final id in pending.skip(start).take(fetchesAtOnce))
          _fetch(owner, id).then((file) {
            if (file != null) fetched[id] = file;
          }),
      ]);
    }
    return fetched;
  }

  Future<FetchedMedia?> _fetch(String owner, MediaId id) async {
    for (var attempt = 1; ; attempt++) {
      final Uint8List? bytes;
      try {
        bytes = await _server.download(id, owner: owner);
      } on MediaFailure {
        if (attempt == fetchAttempts) return null;
        continue;
      }
      if (bytes == null) return null;
      if (mediaTypeOf(bytes) case (final kind, final mimeType)) {
        final copy = MediaId(_newId());
        await _write(copy, bytes);
        return FetchedMedia(
          id: copy,
          kind: kind,
          mimeType: mimeType,
          byteSize: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        );
      }
      return null;
    }
  }

  /// Queues [file], already on the device, for upload, as [addImage] does;
  /// returns its id. Its row joins a caller's transaction.
  Future<MediaId> addFetched(FetchedMedia file) async {
    await _queue(file.id, file.kind, file.mimeType, file.byteSize, file.sha256);
    return file.id;
  }

  /// Deletes each of [files] from the device: fetched, but held by nothing
  /// written.
  Future<void> discardFetched(Iterable<FetchedMedia> files) async {
    for (final file in files) {
      final kept = _file(file.id);
      if (await kept.exists()) await kept.delete();
    }
  }

  Future<MediaId> _add(
    MediaKind kind,
    String mimeType,
    Uint8List bytes,
    String sha256,
  ) async {
    final id = MediaId(_newId());
    await _write(id, bytes);
    await _queue(id, kind, mimeType, bytes.length, sha256);
    return id;
  }

  Future<void> _queue(
    MediaId id,
    MediaKind kind,
    String mimeType,
    int byteSize,
    String sha256,
  ) => _db
      .into(_db.mediaUploads)
      .insert(
        MediaUploadRow(
          id: id.value,
          kind: kind.key,
          mimeType: mimeType,
          byteSize: byteSize,
          sha256: sha256,
          createdAt: _clock(),
        ),
      );

  /// Lets [id] go: it is no longer uploaded, and is queued for deletion from
  /// the server and the device. Only database rows are written, so a caller's
  /// transaction holds it.
  Future<void> release(MediaId id) async {
    await (_db.delete(
      _db.mediaUploads,
    )..where((row) => row.id.equals(id.value))).go();
    await _db
        .into(_db.mediaDeletions)
        .insertOnConflictUpdate(MediaDeletionRow(id: id.value));
  }

  /// The bytes of [id]: the file on the device, or else the server's, which
  /// is then kept on the device. Null when neither holds it or the server
  /// cannot be reached; a later read tries again.
  Future<Uint8List?> read(MediaId id) =>
      _reads[id] ??= _read(id).whenComplete(() {
        _reads.remove(id);
      });

  /// The file of [id] on the device, downloaded and kept first when only
  /// the server holds it, so a player plays it offline from then on; null
  /// as [read] gives it.
  Future<File?> fileOf(MediaId id) async =>
      await read(id) == null ? null : _file(id);

  Future<Uint8List?> _read(MediaId id) async {
    final file = _file(id);
    if (await file.exists()) return file.readAsBytes();
    final Uint8List? bytes;
    try {
      bytes = await _server.download(id);
    } on MediaFailure {
      return null;
    }
    if (bytes != null) await _write(id, bytes);
    return bytes;
  }

  /// Uploads each queued file, then deletes each released one; true when
  /// both queues are empty. A transfer that fails stays queued for the next
  /// run, and the others still run.
  Future<bool> drain() async {
    var settled = true;
    for (final row in await _db.select(_db.mediaUploads).get()) {
      final file = _file(MediaId(row.id));
      try {
        // A file gone from the device has nothing to upload.
        if (await file.exists()) {
          await _server.upload(_toUpload(row), await file.readAsBytes());
        }
        await (_db.delete(
          _db.mediaUploads,
        )..where((queued) => queued.id.equals(row.id))).go();
      } on MediaFailure {
        settled = false;
      }
    }
    for (final row in await _db.select(_db.mediaDeletions).get()) {
      final id = MediaId(row.id);
      try {
        await _server.delete(id);
        final file = _file(id);
        if (await file.exists()) await file.delete();
        await (_db.delete(
          _db.mediaDeletions,
        )..where((queued) => queued.id.equals(row.id))).go();
      } on MediaFailure {
        settled = false;
      }
    }
    return settled;
  }

  File _file(MediaId id) => File('${directory.path}/${id.value}');

  /// Writes [bytes] whole or not at all: a file under its id is complete.
  Future<void> _write(MediaId id, Uint8List bytes) async {
    await directory.create(recursive: true);
    final partial = File('${directory.path}/${id.value}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(_file(id).path);
  }

  static MediaUpload _toUpload(MediaUploadRow row) => MediaUpload(
    id: MediaId(row.id),
    // Only this build's kinds are queued here.
    kind: MediaKind.values.singleWhere((kind) => kind.key == row.kind),
    mimeType: row.mimeType,
    byteSize: row.byteSize,
    sha256: row.sha256,
    createdAt: row.createdAt,
  );
}
