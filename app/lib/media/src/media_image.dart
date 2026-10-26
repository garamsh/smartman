import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'model.dart';
import 'providers.dart';

/// The image [id] names, covering its box, read from the device or else
/// downloaded and kept; [fallback] while it is read and when it cannot be.
class MediaImage extends ConsumerStatefulWidget {
  const MediaImage(this.id, {super.key, required this.fallback});

  final MediaId id;
  final Widget fallback;

  @override
  ConsumerState<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends ConsumerState<MediaImage> {
  late Future<Uint8List?> _bytes = _read();

  Future<Uint8List?> _read() => ref.read(mediaStoreProvider).read(widget.id);

  @override
  void didUpdateWidget(MediaImage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _bytes = _read();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) => switch (snapshot.data) {
      final bytes? => Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.fallback,
      ),
      null => widget.fallback,
    },
  );
}
