import 'models.dart';

/// A venue resolved from its code.
class Venue {
  const Venue({required this.code, required this.name, required this.drop});

  final String code;
  final String name;

  /// As it would appear on the map: fuzzy circle only.
  final NearbyDrop drop;

  factory Venue.fromJson(Map<String, dynamic> j) {
    final d = j['drop'] as Map<String, dynamic>;
    return Venue(
      code: j['code'] as String,
      name: j['name'] as String,
      drop: NearbyDrop.fromJson({
        ...d,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
  }
}
