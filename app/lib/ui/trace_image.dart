import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// A photo from a URL or from memory, fading in over a quiet placeholder.
class TraceImage extends StatelessWidget {
  const TraceImage({super.key, this.url, this.bytes, this.fit = BoxFit.cover});

  final String? url;
  final Uint8List? bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: TraceColors.surfaceHigh,
      alignment: Alignment.center,
      child: const Icon(Icons.photo_rounded, color: TraceColors.textFaint, size: 32),
    );
    if (bytes != null) return Image.memory(bytes!, fit: fit, gaplessPlayback: true);
    if (url == null) return placeholder;
    return Image.network(
      url!,
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, sync) =>
          sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.slow, child: child),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : Stack(fit: StackFit.expand, children: [placeholder, child]),
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
