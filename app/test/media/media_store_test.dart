import 'dart:io';
import 'dart:typed_data';

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

  test('an added sound is uploaded as audio of its own type, and another device keeps the file it plays from after the first read (ADR 0112)', () async {
    final sound = preparedAudio(2500);
    final id = await store.addAudio(sound);
    expect(await store.drain(), isTrue);
    final row = server.rows[id]!;
    expect(
      (row.kind.key, row.mimeType, row.byteSize, row.sha256),
      ('audio', 'audio/mp4', sound.bytes.length, sound.sha256),
    );

    final otherDirectory = newMediaDirectory();
    addTearDown(() => deleteMediaDirectory(otherDirectory));
    final other = storeOver(server, otherDirectory);
    final file = await other.fileOf(id);
    expect(await file!.readAsBytes(), sound.bytes);
    server.offline = true;
    final offline = await other.fileOf(id);
    expect(offline?.path, file.path, reason: 'played offline from the device');
    expect(await offline!.readAsBytes(), sound.bytes);
  });

  test('a sound longer than 60 seconds or larger than 5 MiB is refused, where one at both limits is prepared', () {
    final atLimit = prepareAudio(
      Uint8List(maxAudioBytes),
      mimeType: 'audio/mpeg',
      duration: maxAudioDuration,
    );
    expect(atLimit.duration, maxAudioDuration);

    expect(
      () => prepareAudio(
        Uint8List(maxAudioBytes + 1),
        mimeType: 'audio/mpeg',
        duration: const Duration(seconds: 1),
      ),
      throwsA(isA<MediaTooLarge>()),
    );
    expect(
      () => prepareAudio(
        Uint8List(10),
        mimeType: 'audio/mp4',
        duration: maxAudioDuration + const Duration(milliseconds: 1),
      ),
      throwsA(isA<MediaTooLarge>()),
    );
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

  group("another user's files (ADR 0113)", () {
    const owner = '00000000-0000-4000-8000-00000000000b';
    const photo = MediaId('00000000-0000-4000-8000-0000000000b1');
    const recording = MediaId('00000000-0000-4000-8000-0000000000b2');
    const picked = MediaId('00000000-0000-4000-8000-0000000000b3');
    const unknown = MediaId('00000000-0000-4000-8000-0000000000b4');
    final image = preparedImage(3);

    setUp(() {
      server.shared[(owner, photo)] = image.bytes;
      server.shared[(owner, recording)] = mp4Bytes(1);
      server.shared[(owner, picked)] = mp3Bytes(2);
      server.shared[(owner, unknown)] = Uint8List.fromList([1, 2, 3, 4]);
    });

    test('are read from their owner\'s folder with the kind and type their bytes show, and nothing is written until one is added', () async {
      final fetched = await store.fetchShared(owner, [
        photo,
        recording,
        picked,
        unknown,
      ]);

      expect(
        {
          for (final MapEntry(:key, :value) in fetched.entries)
            key: (value.kind.key, value.mimeType),
        },
        {
          photo: ('image', 'image/jpeg'),
          recording: ('audio', 'audio/mp4'),
          picked: ('audio', 'audio/mpeg'),
        },
        reason: 'bytes of no type the bucket takes are left out',
      );
      expect(await db.select(db.mediaUploads).get(), isEmpty);
      expect(directory.listSync(), isEmpty);
      // Control: the same id in the user's own folder is not the owner's.
      expect(await store.read(photo), isNull);

      final id = await store.addFetched(fetched[photo]!);
      expect(id, isNot(photo));
      expect(await store.read(id), image.bytes);
      expect(await store.drain(), isTrue);
      expect(
        (server.rows[id]!.kind.key, server.rows[id]!.sha256),
        ('image', image.sha256),
      );
      expect(server.files[id], image.bytes);
    });

    test('a file the network fails to bring twice is read on the third try, and one it fails three times is left out', () async {
      server.failingDownloads[photo] = 2;
      server.failingDownloads[recording] = 3;

      final fetched = await store.fetchShared(owner, [photo, recording]);

      expect(fetched.keys, [photo]);
      expect(server.failingDownloads, {photo: 0, recording: 0});
      expect(server.requests, 6);
    });

    test('a file the owner removed is left out without a retry', () async {
      server.shared.remove((owner, photo));

      final fetched = await store.fetchShared(owner, [photo, recording]);

      expect(fetched.keys, [recording]);
      expect(server.requests, 2);
    });
  });
}
