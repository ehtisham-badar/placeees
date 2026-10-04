import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

enum DropType {
  text,
  photo,
  voice;

  static DropType parse(String s) => DropType.values.firstWhere((t) => t.name == s, orElse: () => DropType.text);
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
    this.capsuleUnlockAt,
    this.isRelay = false,
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
  final DateTime? capsuleUnlockAt;
  final bool isRelay;

  bool get canOpenAnywhere => mine || unlocked;

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
      capsuleUnlockAt: badges['capsuleUnlockAt'] == null ? null : DateTime.parse(badges['capsuleUnlockAt'] as String),
      isRelay: badges['relay'] as bool? ?? false,
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
  });

  final String id;
  final DropType type;
  final String? body;
  final String? teaser;
  final String? mediaUrl;

  /// Demo mode only: a photo that never left the device.
  final Uint8List? localImage;

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
  const Passport({required this.unlocked, required this.created});

  final List<PassportEntry> unlocked;
  final List<PassportEntry> created;

  int get peopleReached => created.fold(0, (sum, e) => sum + e.unlockCount);
}

class AuthResult {
  const AuthResult(this.token, this.user);

  final String token;
  final User user;
}
