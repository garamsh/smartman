import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../media/media.dart';
import 'content.dart';

/// The side of the play control, large enough to find and hit at a glance
/// on a study card (ADR 0112).
const audioControlSize = 64.0;

/// [duration] as minutes and seconds, `0:07`, rounded up to the second.
String audioLength(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A sound block: a round play control named "소리 듣기", which plays it
/// through `media`'s player, and its length under it (ADR 0112).
class AudioBlockView extends StatelessWidget {
  const AudioBlockView(this.audio, {super.key});

  final AudioContent audio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpace.s4,
      children: [
        SizedBox.square(
          dimension: audioControlSize,
          child: IconButton.filled(
            tooltip: l10n.playAudio,
            style: IconButton.styleFrom(
              backgroundColor: colors.brandTint,
              foregroundColor: colors.ink,
            ),
            iconSize: audioControlSize / 2,
            icon: const Icon(LucideIcons.volume2),
            onPressed: () => playAudio(context, audio),
          ),
        ),
        ExcludeSemantics(
          child: Text(
            audioLength(audio.duration),
            style: AppType.caption.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// Plays [audio], and says so in a snack bar when it cannot be read or
/// played.
Future<void> playAudio(BuildContext context, AudioContent audio) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final unplayable = AppLocalizations.of(context).audioUnplayable;
  final playback = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(audioPlaybackProvider);
  if (!await playback.play(audio.media)) {
    messenger?.showSnackBar(SnackBar(content: Text(unplayable)));
  }
}

/// A sound block as the editor edits it: its sound, once one is recorded or
/// picked.
class AudioDraft {
  AudioDraft([this.audio]);

  AudioContent? audio;
}

/// Why a sound block's fields show a line under them.
enum _Problem { unreadable, tooLarge, microphone }

/// The sound block that holds the recorder, null while none does. The
/// device has one recorder, so "녹음" is off in every other block until the
/// holder has stopped (ADR 0112).
final recordingBlockProvider = NotifierProvider<RecordingBlock, Object?>(
  RecordingBlock.new,
);

class RecordingBlock extends Notifier<Object?> {
  @override
  Object? build() => null;

  /// Whether [block] now holds the recorder: it did, or no block did.
  bool claim(Object block) {
    if (state != null && state != block) return false;
    state = block;
    return true;
  }

  /// Lets go of the recorder, if [block] holds it.
  void release(Object block) {
    if (state == block) state = null;
  }
}

/// A sound block's fields: "녹음하기" and "파일에서 고르기" until a sound is
/// in it; while recording, the time so far against the limit and
/// "녹음 끝내기", which the limit presses itself; then the sound's play
/// control and length, "다시 녹음", "다른 파일 고르기" and "소리 빼기"
/// (ADR 0112). The microphone is asked for on the first recording alone.
class AudioBlockFields extends ConsumerStatefulWidget {
  const AudioBlockFields({
    super.key,
    required this.draft,
    required this.showErrors,
    required this.onChanged,
    required this.onStored,
  });

  final AudioDraft draft;
  final bool showErrors;
  final VoidCallback onChanged;

  /// Called with each sound stored for the block, so the editor can let go
  /// of one it does not save.
  final ValueChanged<MediaId> onStored;

  @override
  ConsumerState<AudioBlockFields> createState() => _AudioBlockFieldsState();
}

class _AudioBlockFieldsState extends ConsumerState<AudioBlockFields> {
  var _busy = false;
  _Problem? _problem;

  /// The whole seconds the recording under way has run; null while none is.
  int? _recorded;
  Timer? _tick;
  late final AudioRecording _recording = ref.read(audioRecordingProvider);
  late final RecordingBlock _recorder = ref.read(
    recordingBlockProvider.notifier,
  );

  @override
  void dispose() {
    _tick?.cancel();
    if (_recorded != null) unawaited(_recording.cancel());
    _recorder.release(this);
    super.dispose();
  }

  Future<void> _record() async {
    if (!_recorder.claim(this)) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await _recording.start();
      if (!mounted) {
        await _recording.cancel();
        return;
      }
      setState(() => _recorded = 0);
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        final recorded = (_recorded ?? 0) + 1;
        setState(() => _recorded = recorded);
        // The limit stops the recording itself.
        if (recorded >= maxAudioDuration.inSeconds) _stopRecording();
      });
    } on MicrophoneDenied {
      if (mounted) setState(() => _problem = _Problem.microphone);
    } on MediaUnreadable {
      if (mounted) setState(() => _problem = _Problem.unreadable);
    } finally {
      // A recording under way keeps the recorder.
      if (_recorded == null) _recorder.release(this);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    _tick?.cancel();
    if (_recorded == null) return;
    setState(() {
      _recorded = null;
      _busy = true;
    });
    await _store(_recording.stop);
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    await _store(ref.read(audioPickProvider).pick);
  }

  /// Stores the sound [take] gives, if any, and puts it in the block.
  Future<void> _store(Future<PreparedAudio?> Function() take) async {
    // Read before the waits: a pick can end after the editor is left.
    final store = ref.read(mediaStoreProvider);
    try {
      final taken = await take();
      if (taken == null) return;
      final media = await store.addAudio(taken);
      // Stored once the fields are gone, it has no block to hold it.
      if (!mounted) {
        await store.release(media);
        return;
      }
      widget.onStored(media);
      setState(
        () => widget.draft.audio = AudioContent(
          media: media,
          duration: taken.duration,
        ),
      );
      widget.onChanged();
    } on MediaTooLarge {
      if (mounted) setState(() => _problem = _Problem.tooLarge);
    } on MediaUnreadable {
      if (mounted) setState(() => _problem = _Problem.unreadable);
    } finally {
      _recorder.release(this);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove() {
    setState(() => widget.draft.audio = null);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final error = AppType.caption.copyWith(color: colors.dontKnowText);
    final audio = widget.draft.audio;
    final recorded = _recorded;
    // Another block holds the one recorder.
    final recorderTaken = switch (ref.watch(recordingBlockProvider)) {
      final holder? => holder != this,
      null => false,
    };
    final problem = switch (_problem) {
      _Problem.unreadable => l10n.audioUnreadable,
      _Problem.tooLarge => l10n.audioTooLarge(maxAudioDuration.inSeconds),
      _Problem.microphone => l10n.microphoneDenied,
      null when widget.showErrors && audio == null && recorded == null =>
        l10n.audioRequired,
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s8,
      children: [
        if (recorded != null) ...[
          Text(
            l10n.audioRecording(
              audioLength(Duration(seconds: recorded)),
              audioLength(maxAudioDuration),
            ),
            textAlign: TextAlign.center,
            style: AppType.bodyStrong,
          ),
          AppButton(
            label: l10n.audioStopRecording,
            // Outlined: the bottom bar holds the screen's one primary fill.
            variant: AppButtonVariant.secondary,
            onPressed: _stopRecording,
          ),
        ] else if (audio != null) ...[
          Center(child: AudioBlockView(audio)),
          Row(
            spacing: AppSpace.s8,
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.audioRecordAgain,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy || recorderTaken ? null : _record,
                ),
              ),
              Expanded(
                child: AppButton(
                  label: l10n.audioPickAnother,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : _pick,
                ),
              ),
            ],
          ),
          AppButton(
            label: l10n.audioRemove,
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : _remove,
          ),
        ] else
          Row(
            spacing: AppSpace.s8,
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.audioRecord,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy || recorderTaken ? null : _record,
                ),
              ),
              Expanded(
                child: AppButton(
                  label: l10n.audioPick,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : _pick,
                ),
              ),
            ],
          ),
        Semantics(
          liveRegion: true,
          child: problem == null
              ? const SizedBox.shrink()
              : Text(problem, style: error),
        ),
      ],
    );
  }
}
