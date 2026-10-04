import 'package:intl/intl.dart';

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 30) return '${d.inDays} days ago';
  if (d.inDays < 365) return DateFormat.MMMd().format(t);
  return DateFormat.yMMMd().format(t);
}

String distanceLabel(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';
}

String countdown(DateTime until, {DateTime? now}) {
  final d = until.difference(now ?? DateTime.now());
  if (d.isNegative) return 'open now';
  if (d.inDays >= 1) return 'opens in ${d.inDays} d';
  if (d.inHours >= 1) return 'opens in ${d.inHours} h';
  return 'opens in ${d.inMinutes} min';
}

String peopleCount(int n) => switch (n) {
      0 => 'No one else has found this yet',
      1 => '1 person has been here',
      _ => '$n people have been here',
    };
