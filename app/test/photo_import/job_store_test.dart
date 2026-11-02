import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowno/photo_import/photo_import.dart';

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('job_store'));
  tearDown(() => temp.delete(recursive: true));

  final jpeg = Uint8List.fromList([1, 2, 3]);

  test('a photo that cannot be written is not kept, where one in a writable directory is', () async {
    final kept = FileImportJobStore(Directory('${temp.path}/job'));
    final key = await kept.putPhoto(jpeg);
    expect(await kept.photo(key), jpeg, reason: 'the control is kept');

    // A file where the store's directory would be, so nothing is written.
    final blocked = File('${temp.path}/blocked')..writeAsBytesSync([0]);
    final refused = FileImportJobStore(Directory(blocked.path));
    await expectLater(refused.putPhoto(jpeg), throwsA(isA<PhotoNotKept>()));
  });

  test(
    'a photo whose file is gone is not kept, where one still on disk is read',
    () async {
      final store = FileImportJobStore(Directory('${temp.path}/job'));
      final key = await store.putPhoto(jpeg);
      final gone = await store.putPhoto(jpeg);
      File('${temp.path}/job/$gone').deleteSync();

      expect(await store.photo(key), jpeg, reason: 'the control is read');
      await expectLater(store.photo(gone), throwsA(isA<PhotoNotKept>()));
    },
  );
}
