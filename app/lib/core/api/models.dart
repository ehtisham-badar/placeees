import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'conditions.dart';
import 'signature.dart';
import 'social.dart';

enum DropType {
  text('text'),
  photo('photo'),
  voice('voice'),
  thenNow('then_now');

  const DropType(this.wire);

  /// The API's name for this type.
  final String wire;

  static DropType parse(String s) => DropType.values.firstWhere((t) => t.wire == s, orElse: () => DropType.text);
}

class User {
  const User({required this.id, required this.handle, required this.hasHomeZone});

  final String id;
  final String? handle;
  final bool hasHomeZone;

  factory User.fromJson(Map<String, dynamic> j) =>
      User(id: j['id'] as String, handle: j['handle'] as String?, hasHomeZone: j['hasHomeZone'] as bool? ?? false);
}

/// A single GPS fix, sent with every location-bearing request (spec F-04).
class LocationFix {
  const LocationFix({required this.lat, required this.lng, required this.accuracy, required this.timestamp, this.speed});

  final double lat;
  final double lng;
  final double accuracy;
  final double? speed;
  final DateTime timestamp;

  LatLng get point => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        if (speed != null) 'speed': speed,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };
}

/// A drop as it appears on the map: only a fuzzy circle, never the true point.
class NearbyDrop {
  const NearbyDrop({
    required this.id,
    required this.type,
    required this.teaser,
    required this.createdAt,
    required this.center,
    required this.radius,
    required this.mine,
    required this.unlocked,
    required this.pending,
    this.hasCondition = false,
    this.conditionKinds = const [],
    this.conditions,
    this.capsuleUnlockAt,
    this.forYou = false,
    this.isRelay = false,
    this.trail,
    this.circle,
    this.relayHops = 0,
  });

  final String id;
  final DropType type;
  final String? teaser;
  final DateTime createdAt;
  final LatLng center;
  final double radius;
  final bool mine;
  final bool unlocked;
  final bool pending;
  final bool hasCondition;

  /// Which kinds of rule apply (`sun`, `night`, `weather`, `timeRange`, `dateRange`): shown as icons.
  final List<String> conditionKinds;

  /// The exact rules, only when the creator chose to reveal them (or it's your own drop).
  final List<DropCondition>? conditions;
  final DateTime? capsuleUnlockAt;

  /// A time capsule addressed to you.
  final bool forYou;
  final bool isRelay;
  final TrailRef? trail;
  final CircleRef? circle;
  final int relayHops;

  bool get canOpenAnywhere => mine || unlocked;
  bool get isSealed => capsuleUnlockAt != null && DateTime.now().isBefore(capsuleUnlockAt!);

  NearbyDrop copyWith({bool? unlocked}) => NearbyDrop(
        id: id,
        type: type,
        teaser: teaser,
        createdAt: createdAt,
        center: center,
        radius: radius,
        mine: mine,
        unlocked: unlocked ?? this.unlocked,
        pending: pending,
        hasCondition: hasCondition,
        conditionKinds: conditionKinds,
        conditions: conditions,
        capsuleUnlockAt: capsuleUnlockAt,
        forYou: forYou,
        isRelay: isRelay,
        trail: trail,
        circle: circle,
        relayHops: relayHops,
      );

  factory NearbyDrop.fromJson(Map<String, dynamic> j) {
    final c = j['center'] as Map<String, dynamic>;
    final badges = (j['badges'] as Map<String, dynamic>?) ?? const {};
    return NearbyDrop(
      id: j['id'] as String,
      type: DropType.parse(j['type'] as String),
      teaser: j['teaser'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      center: LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
      radius: (j['radius'] as num).toDouble(),
      mine: j['mine'] as bool? ?? false,
      unlocked: j['unlocked'] as bool? ?? false,
      pending: j['pending'] as bool? ?? false,
      hasCondition: badges['condition'] as bool? ?? false,
      conditionKinds: ((badges['conditionKinds'] as List?) ?? const []).cast<String>(),
      conditions: (badges['conditions'] as Map<String, dynamic>?)?['all'] == null
          ? null
          : [
              for (final c in (badges['conditions'] as Map<String, dynamic>)['all'] as List)
                ?DropCondition.fromJson(c as Map<String, dynamic>),
            ],
      capsuleUnlockAt: badges['capsuleUnlockAt'] == null ? null : DateTime.parse(badges['capsuleUnlockAt'] as String),
      forYou: badges['forYou'] as bool? ?? false,
      isRelay: badges['relay'] as bool? ?? false,
      trail: TrailRef.fromJson(badges['trail']),
      circle: CircleRef.fromJson(badges['circle']),
      relayHops: (badges['relayHops'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Full drop content, only available after an unlock (or to its creator).
class DropContent {
  const DropContent({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.unlockCount,
    required this.mine,
    this.body,
    this.teaser,
    this.mediaUrl,
    this.authorHandle,
    this.unlockedAt,
    this.pending = false,
    this.localImage,
    this.trail,
    this.circle,
    this.relay,
    this.angle,
  });

  final String id;
  final DropType type;
  final String? body;
  final String? teaser;
  final String? mediaUrl;

  /// Demo mode only: a photo that never left the device.
  final Uint8List? localImage;
  final TrailRef? trail;
  final CircleRef? circle;
  final RelayInfo? relay;

  /// Then/Now drops only.
  final CaptureAngle? angle;

  /// Null for anonymous drops.
  final String? authorHandle;
  final DateTime createdAt;
  final DateTime? unlockedAt;
  final int unlockCount;
  final bool mine;
  final bool pending;

  factory DropContent.fromJson(Map<String, dynamic> j) => DropContent(
        id: j['id'] as String,
        type: DropType.parse(j['type'] as String),
        body: j['body'] as String?,
        teaser: j['teaser'] as String?,
        mediaUrl: j['mediaUrl'] as String?,
        authorHandle: (j['author'] as Map<String, dynamic>?)?['handle'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        unlockedAt: j['unlockedAt'] == null ? null : DateTime.parse(j['unlockedAt'] as String),
        unlockCount: (j['unlockCount'] as num?)?.toInt() ?? 0,
        mine: j['mine'] as bool? ?? false,
        pending: j['status'] == 'pending_moderation',
        trail: TrailRef.fromJson(j['trail']),
        circle: CircleRef.fromJson(j['circle']),
        relay: RelayInfo.fromJson(j['relay']),
        angle: CaptureAngle.fromJson(j['thenNow']),
      );
}

class PassportEntry {
  const PassportEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    this.teaser,
    this.body,
    this.unlockedAt,
    this.authorHandle,
    this.unlockCount = 0,
    this.status,
  });

  final String id;
  final DropType type;
  final String? teaser;
  final String? body;
  final DateTime createdAt;
  final DateTime? unlockedAt;
  final String? authorHandle;
  final int unlockCount;
  final String? status;

  bool get inReview => status == 'pending_moderation';
  bool get rejected => status == 'rejected';

  factory PassportEntry.fromJson(Map<String, dynamic> j) => PassportEntry(
        id: j['id'] as String,
        type: DropType.parse(j['type'] as String),
        teaser: j['teaser'] as String?,
        body: j['body'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        unlockedAt: j['unlockedAt'] == null ? null : DateTime.parse(j['unlockedAt'] as String),
        authorHandle: j['authorHandle'] as String?,
        unlockCount: (j['unlockCount'] as num?)?.toInt() ?? 0,
        status: j['status'] as String?,
      );
}

class Passport {
  const Passport({required this.unlocked, required this.created, this.stamps = const []});

  final List<PassportEntry> unlocked;
  final List<PassportEntry> created;

  /// Completed trails.
  final List<Stamp> stamps;

  int get peopleReached => created.fold(0, (sum, e) => sum + e.unlockCount);
}

class AuthResult {
  const AuthResult(this.token, this.user);

  final String token;
  final User user;
}

/// The true point of a drop, revealed briefly once you're within 100 m (spec F-07).
class NearHint {
  const NearHint({required this.point, required this.expiresAt});

  final LatLng point;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);

  factory NearHint.fromJson(Map<String, dynamic> j) {
    final p = j['point'] as Map<String, dynamic>;
    return NearHint(
      point: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
      expiresAt: DateTime.parse(j['expiresAt'] as String),
    );
  }
}
