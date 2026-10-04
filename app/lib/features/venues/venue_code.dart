/// Pulls a venue code out of whatever was scanned or tapped (spec F-16):
/// `trace://v/CODE`, `https://<any host>/v/CODE`, or a bare 8-character code.
String? venueCodeFrom(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  String? candidate;
  if (uri != null && uri.scheme == 'trace' && uri.host == 'v' && uri.pathSegments.isNotEmpty) {
    candidate = uri.pathSegments.first;
  } else if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    final segs = uri.pathSegments;
    if (segs.length >= 2 && segs[segs.length - 2] == 'v') candidate = segs.last;
  } else {
    candidate = text;
  }
  final code = candidate?.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  return code != null && RegExp(r'^[2-9A-HJKMNP-Z]{8}$').hasMatch(code) ? code : null;
}
