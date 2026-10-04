import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

const maxPhotoBytes = 1500 * 1024;

/// Re-encodes a photo to JPEG under 1.5 MB (spec F-02), stepping quality down as needed.
Future<Uint8List?> compressPhoto(String path) async {
  for (final (quality, side) in const [(85, 2048), (75, 1800), (65, 1600), (55, 1400)]) {
    final out = await FlutterImageCompress.compressWithFile(
      path,
      format: CompressFormat.jpeg,
      quality: quality,
      minWidth: side,
      minHeight: side,
      keepExif: false, // strips GPS and device metadata
    );
    if (out != null && out.lengthInBytes <= maxPhotoBytes) return out;
  }
  return null;
}
