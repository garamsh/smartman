import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/media/media.dart';
import 'package:uuid/uuid.dart';

import 'fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeMediaServer server;
  late Directory directory;
  late MediaStore store;

  MediaStore storeOver(MediaServer server, Directory directory) => MediaStore(
    db,
    server,
    directory: directory,
    clock: () => DateTime.utc(2026, 10, 26),
    newId: const Uuid().v4,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeMediaServer();
    directory = newMediaDirectory();
    store = storeOver(server, directory);
  });

  tearDown(() async {
    await db.close();
    await deleteMediaDirectory(directory);
  });

  test(
    'an added image reads back at once from the device, before any upload',
    () async {
      server.offline = true;
      final image = preparedImage(1);
      final id = await store.addImage(image);

      expect(await store.read(id), image.bytes);
      expect(server.requests, 0, reason: 'the read is the device file');
      expect(File('${directory.path}/${id.value}').existsSync(), isTrue);
    },
  );

  test('a drain uploads each queued image with its row, then leaves the queue empty', () async {
    final image = preparedImage(1);
    final id = await store.addImage(image);

    expect(await store.drain(), isTrue);
    expect(server.files[id], image.bytes);
    final row = server.rows[id]!;
    expect(
      (row.mimeType, row.byteSize, row.sha256),
      ('image/jpeg', image.bytes.length, image.sha256),
    );
    expect(await db.select(db.mediaUploads).get(), isEmpty);
  });

  test('a drain that cannot reach the server keeps the image queued, and a later one uploads it', () async {
    final image = preparedImage(4);
    final id = await store.addImage(image);
    server.offline = true;

    expect(await store.drain(), isFalse);
    expect(await db.select(db.mediaUploads).get(), hasLength(1));

    server.offline = false;
    expect(await store.drain(), isTrue);
    expect(server.files[id], image.bytes);
  });

  test('a released image is never uploaded, and a drain deletes it from the server and the device', () async {
    final stored = await store.addImage(preparedImage(1));
    await store.drain();
    final unsent = await store.addImage(preparedImage(2));

    await store.release(stored);
    await store.release(unsent);
    expect(await store.drain(), isTrue);

    expect(server.files, isEmpty);
    expect(server.rows, isEmpty);
    expect(File('${directory.path}/${stored.value}').existsSync(), isFalse);
    expect(File('${directory.path}/${unsent.value}').existsSync(), isFalse);
    expect(await db.select(db.mediaDeletions).get(), isEmpty);
  });

  test(
    'a deletion the server does not answer stays queued until it does',
    () async {
      final id = await store.addImage(preparedImage(1));
      await store.drain();
      await store.release(id);
      server.offline = true;

      expect(await store.drain(), isFalse);
      expect(await db.select(db.mediaDeletions).get(), hasLength(1));

      server.offline = false;
      expect(await store.drain(), isTrue);
      expect(server.files, isEmpty);
    },
  );

  test(
    'an image another device stored is downloaded once and kept on this device',
    () async {
      final otherDirectory = newMediaDirectory();
      addTearDown(() => deleteMediaDirectory(otherDirectory));
      final image = preparedImage(7);
      final id = await store.addImage(image);
      await store.drain();
      final other = storeOver(server, otherDirectory);

      expect(await other.read(id), image.bytes);
      server.offline = true;
      expect(await other.read(id), image.bytes, reason: 'kept on the device');
    },
  );

  test('an image neither the device nor a reachable server holds reads as null, and a later read tries again', () async {
    const id = MediaId('00000000-0000-4000-8000-0000000000aa');
    server.offline = true;
    expect(await store.read(id), isNull);

    server.offline = false;
    expect(await store.read(id), isNull, reason: 'the server holds none');
    final image = preparedImage(9);
    server.files[id] = image.bytes;
    expect(await store.read(id), image.bytes);
  });
}
