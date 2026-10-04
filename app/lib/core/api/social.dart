import 'package:latlong2/latlong.dart' show LatLng;

import 'models.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

/// A location-bound reply (spec F-11).
class Echo {
  const Echo({
    required this.id,
    required this.body,
    required this.createdAt,
    this.authorHandle,
    this.mine = false,
    this.pending = false,
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final String? authorHandle;
  final bool mine;
  final bool pending;

  factory Echo.fromJson(Map<String, dynamic> j) => Echo(
        id: j['id'] as String,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        authorHandle: j['authorHandle'] as String?,
        mine: j['mine'] as bool? ?? false,
        pending: j['pending'] as bool? ?? false,
      );
}

/// Where a drop sits in a trail (spec F-10).
class TrailRef {
  const TrailRef({required this.id, required this.title, required this.seq, required this.total, this.nextClue, this.completedAt});

  final String id;
  final String title;
  final int seq;
  final int total;

  /// Revealed once this stop is unlocked; null on the last stop.
  final String? nextClue;
  final DateTime? completedAt;

  bool get isLast => seq == total;

  static TrailRef? fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    return TrailRef(
      id: v['id'] as String,
      title: v['title'] as String,
      seq: (v['seq'] as num).toInt(),
      total: (v['total'] as num).toInt(),
      nextClue: v['nextClue'] as String?,
      completedAt: _date(v['completedAt']),
    );
  }
}

class CircleRef {
  const CircleRef({required this.id, required this.name});

  final String id;
  final String name;

  static CircleRef? fromJson(Object? v) =>
      v is Map<String, dynamic> ? CircleRef(id: v['id'] as String, name: v['name'] as String) : null;
}

class TrailStop {
  const TrailStop({
    required this.seq,
    required this.unlocked,
    required this.reached,
    this.clue,
    this.dropId,
    this.type,
    this.teaser,
    this.areaCenter,
  });

  final int seq;
  final bool unlocked;

  /// The previous stop is found, so this one's clue is revealed and it's on the map.
  final bool reached;
  final String? clue;
  final String? dropId;
  final DropType? type;
  final String? teaser;
  final LatLng? areaCenter;

  factory TrailStop.fromJson(Map<String, dynamic> j) {
    final drop = j['drop'] as Map<String, dynamic>?;
    final area = j['area'] as Map<String, dynamic>?;
    final center = area?['center'] as Map<String, dynamic>?;
    return TrailStop(
      seq: (j['seq'] as num).toInt(),
      unlocked: j['unlocked'] as bool,
      reached: j['reached'] as bool,
      clue: j['clue'] as String?,
      dropId: j['dropId'] as String? ?? drop?['id'] as String?,
      type: drop == null ? null : DropType.parse(drop['type'] as String),
      teaser: drop?['teaser'] as String?,
      areaCenter: center == null ? null : LatLng((center['lat'] as num).toDouble(), (center['lng'] as num).toDouble()),
    );
  }
}

class Trail {
  const Trail({
    required this.id,
    required this.title,
    required this.stops,
    required this.mine,
    this.creatorHandle,
    this.completedAt,
  });

  final String id;
  final String title;
  final String? creatorHandle;
  final bool mine;
  final DateTime? completedAt;
  final List<TrailStop> stops;

  int get found => stops.where((s) => s.unlocked).length;
  TrailStop? get current => stops.where((s) => s.reached && !s.unlocked).firstOrNull;

  factory Trail.fromJson(Map<String, dynamic> j) => Trail(
        id: j['id'] as String,
        title: j['title'] as String,
        creatorHandle: (j['creator'] as Map<String, dynamic>?)?['handle'] as String?,
        mine: j['mine'] as bool? ?? false,
        completedAt: _date(j['completedAt']),
        stops: [for (final s in j['stops'] as List) TrailStop.fromJson(s as Map<String, dynamic>)],
      );
}

class Stamp {
  const Stamp({required this.trailId, required this.title, required this.completedAt, required this.stops});

  final String trailId;
  final String title;
  final DateTime completedAt;
  final int stops;

  factory Stamp.fromJson(Map<String, dynamic> j) => Stamp(
        trailId: j['trailId'] as String,
        title: j['title'] as String,
        completedAt: DateTime.parse(j['completedAt'] as String),
        stops: (j['stops'] as num).toInt(),
      );
}

class CircleMember {
  const CircleMember({required this.handle, required this.isOwner});

  final String handle;
  final bool isOwner;
}

/// A private group (spec F-12).
class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.memberCount,
    required this.isOwner,
    this.members = const [],
  });

  final String id;
  final String name;
  final String inviteCode;
  final int memberCount;
  final bool isOwner;
  final List<CircleMember> members;

  factory Circle.fromJson(Map<String, dynamic> j) => Circle(
        id: j['id'] as String,
        name: j['name'] as String,
        inviteCode: j['inviteCode'] as String,
        memberCount: (j['memberCount'] as num).toInt(),
        isOwner: j['isOwner'] as bool? ?? false,
        members: [
          for (final m in (j['members'] as List?) ?? const [])
            CircleMember(handle: (m as Map)['handle'] as String? ?? '?', isOwner: m['isOwner'] as bool? ?? false),
        ],
      );
}
