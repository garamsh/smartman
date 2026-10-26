import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import 'failure.dart';
import 'media_store.dart';
import 'model.dart';

/// Plays a stored audio file by its id, one at a time.
abstract interface class AudioPlayback {
  /// Plays [id] from its start, stopping whatever plays; the file is read
  /// from the device, or downloaded and kept there first. False when no
  /// file can be read or played.
  Future<bool> play(MediaId id);

  /// Stops what plays, if anything.
  Future<void> stop();
}

/// Records from the microphone into an audio file made ready to store.
abstract interface class AudioRecording {
  /// Starts recording. The first call on a device asks for the microphone;
  /// throws [MicrophoneDenied] when it is refused, and [MediaUnreadable]
  /// when the recorder cannot start.
  Future<void> start();

  /// Stops recording and returns what was recorded, or null when nothing
  /// was. Throws [MediaUnreadable] when the recording cannot be read.
  Future<PreparedAudio?> stop();

  /// Stops recording and keeps nothing.
  Future<void> cancel();
}

/// Lets the user pick one audio file, made ready to store.
abstract interface class AudioPick {
  /// The audio file picked, or null when the user cancels. Throws
  /// [MediaUnreadable] when the picker cannot be opened or the file cannot
  /// be read or played, and [MediaTooLarge] when it plays longer than
  /// [maxAudioDuration] or holds more than [maxAudioBytes].
  Future<PreparedAudio?> pick();
}

/// The MIME type of an audio file named with [extension], among the types
/// the bucket accepts; null for any other.
String? audioMimeType(String? extension) => switch (extension?.toLowerCase()) {
  'm4a' || 'mp4' || 'aac' => 'audio/mp4',
  'mp3' => 'audio/mpeg',
  _ => null,
};

/// [bytes] of [mimeType] that play for [duration], as stored; throws
/// [MediaTooLarge] past either limit.
PreparedAudio prepareAudio(
  Uint8List bytes, {
  required String mimeType,
  required Duration duration,
}) {
  if (duration > maxAudioDuration || bytes.length > maxAudioBytes) {
    throw MediaTooLarge('${bytes.length} bytes over $duration');
  }
  return PreparedAudio(
    bytes,
    sha256.convert(bytes).toString(),
    mimeType: mimeType,
    duration: duration,
  );
}

/// The device's player through `just_audio`, playing from the files
/// [MediaStore] keeps.
final class DeviceAudioPlayback implements AudioPlayback {
  DeviceAudioPlayback(this._store);

  final MediaStore _store;
  AudioPlayer? _player;

  @override
  Future<bool> play(MediaId id) async {
    final file = await _store.fileOf(id);
    if (file == null) return false;
    final player = _player ??= AudioPlayer();
    try {
      await player.stop();
      await player.setFilePath(file.path);
      // Completes when playback ends, so it is not awaited.
      unawaited(player.play());
      return true;
    } on PlayerException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stop() async => _player?.stop();

  Future<void> dispose() async => _player?.dispose();
}

/// The device's microphone through `record`, recording AAC in an MPEG-4
/// container, which both phones record and play (ADR 0112).
final class DeviceAudioRecording implements AudioRecording {
  DeviceAudioRecording();

  final _recorder = AudioRecorder();
  final _clock = Stopwatch();

  @override
  Future<void> start() async {
    try {
      // Asks only while the user has not answered.
      if (!await _recorder.hasPermission()) {
        throw const MicrophoneDenied('the microphone was refused');
      }
      final path =
          '${Directory.systemTemp.path}/recording-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          numChannels: 1,
        ),
        path: path,
      );
      _clock
        ..reset()
        ..start();
    } on PlatformException catch (cause) {
      throw MediaUnreadable(cause);
    }
  }

  @override
  Future<PreparedAudio?> stop() async {
    _clock.stop();
    final String? path;
    try {
      path = await _recorder.stop();
    } on PlatformException catch (cause) {
      throw MediaUnreadable(cause);
    }
    if (path == null) return null;
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return prepareAudio(
        bytes,
        mimeType: 'audio/mp4',
        // The editor stops at the limit, so a few milliseconds over it are
        // the stop's own delay.
        duration: _clock.elapsed > maxAudioDuration
            ? maxAudioDuration
            : _clock.elapsed,
      );
    } on IOException catch (cause) {
      throw MediaUnreadable(cause);
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> cancel() async {
    _clock.stop();
    try {
      await _recorder.cancel();
    } on PlatformException {
      // Nothing was kept either way.
    }
  }

  Future<void> dispose() => _recorder.dispose();
}

/// The device's file picker through `file_picker`, taking an M4A or MP3
/// file, whose length `just_audio` reads.
final class DeviceAudioPick implements AudioPick {
  const DeviceAudioPick();

  @override
  Future<PreparedAudio?> pick() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['m4a', 'mp3'],
      );
    } on PlatformException catch (cause) {
      throw MediaUnreadable(cause);
    }
    if (file == null) return null;
    final mimeType = audioMimeType(file.extension);
    if (mimeType == null) {
      throw MediaUnreadable('not an M4A or MP3 file: ${file.name}');
    }
    if ((await file.length() ?? 0) > maxAudioBytes) {
      throw MediaTooLarge('${file.name} is over $maxAudioBytes bytes');
    }
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on IOException catch (cause) {
      throw MediaUnreadable(cause);
    }
    return prepareAudio(
      bytes,
      mimeType: mimeType,
      duration: await _durationOf(bytes, file.extension!),
    );
  }

  /// How long [bytes] play, read by a player from a file of [extension].
  static Future<Duration> _durationOf(Uint8List bytes, String extension) async {
    final probe = File(
      '${Directory.systemTemp.path}/probe-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    final player = AudioPlayer();
    try {
      await probe.writeAsBytes(bytes, flush: true);
      final duration = await player.setFilePath(probe.path);
      if (duration == null || duration == Duration.zero) {
        throw const MediaUnreadable('the file has no length');
      }
      return duration;
    } on PlayerException catch (cause) {
      throw MediaUnreadable(cause);
    } on PlatformException catch (cause) {
      throw MediaUnreadable(cause);
    } finally {
      await player.dispose();
      if (await probe.exists()) await probe.delete();
    }
  }
}
