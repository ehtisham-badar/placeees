import 'dart:typed_data';

import 'package:latlong2/latlong.dart' show LatLng;

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
LatLng _point(Object? v) {
  final m = v as Map<String, dynamic>;
  return LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
}

/// Relay state on an opened drop (spec F-13).
class RelayInfo {
  const RelayInfo({required this.hops, required this.carrying, required this.canPickUp, this.carryDeadline});

  final int hops;

  /// You're carrying it right now.
  final bool carrying;
  final bool canPickUp;
  final DateTime? carryDeadline;

  static RelayInfo? fromJson(Object? v) {
    if (v is! Map<String, dynamic>) return null;
    return RelayInfo(
      hops: (v['hops'] as num?)?.toInt() ?? 0,
      carrying: v['carrying'] as bool? ?? false,
      canPickUp: v['canPickUp'] as bool? ?? false,
      carryDeadline: _date(v['carryDeadline']),
    );
  }
}

class RelayHop {
  const RelayHop({required this.to, required this.distanceM, this.handle, this.pickedAt, this.droppedAt, this.note});

  final String? handle;
  final DateTime? pickedAt;
  final DateTime? droppedAt;
  final double distanceM;
  final String? note;
  final LatLng to;

  factory RelayHop.fromJson(Map<String, dynamic> j) => RelayHop(
        handle: j['handle'] as String?,
        pickedAt: _date(j['pickedAt']),
        droppedAt: _date(j['droppedAt']),
        distanceM: (j['distanceM'] as num).toDouble(),
        note: j['note'] as String?,
        to: _point(j['to']),
      );
}

/// Everywhere a relay has been. Points are fuzzed like map markers.
class RelayJourney {
  const RelayJourney({
    required this.origin,
    required this.originAt,
    required this.hops,
    required this.totalDistanceM,
    this.originHandle,
    this.carriedBy,
  });

  final LatLng origin;
  final DateTime originAt;
  final String? originHandle;
  final List<RelayHop> hops;
  final double totalDistanceM;

  /// Handle of whoever has it in their pocket now.
  final String? carriedBy;

  List<LatLng> get path => [origin, for (final h in hops) h.to];

  factory RelayJourney.fromJson(Map<String, dynamic> j) {
    final o = j['origin'] as Map<String, dynamic>;
    return RelayJourney(
      origin: _point(o),
      originAt: DateTime.parse(o['at'] as String),
      originHandle: o['handle'] as String?,
      hops: [for (final h in j['hops'] as List) RelayHop.fromJson(h as Map<String, dynamic>)],
      totalDistanceM: (j['totalDistanceM'] as num).toDouble(),
      carriedBy: (j['carriedBy'] as Map<String, dynamic>?)?['handle'] as String?,
    );
  }
}

/// A relay in your pocket.
class CarriedRelay {
  const CarriedRelay({
    required this.id,
    required this.pickedAt,
    required this.deadlineAt,
    required this.pickup,
    this.teaser,
  });

  final String id;
  final String? teaser;
  final DateTime pickedAt;
  final DateTime deadlineAt;

  /// Exactly where you picked it up; the next spot must be ≥ 1 km from here.
  final LatLng pickup;

  factory CarriedRelay.fromJson(Map<String, dynamic> j) => CarriedRelay(
        id: j['id'] as String,
        teaser: j['teaser'] as String?,
        pickedAt: DateTime.parse(j['pickedAt'] as String),
        deadlineAt: DateTime.parse(j['deadlineAt'] as String),
        pickup: LatLng((j['pickupLat'] as num).toDouble(), (j['pickupLng'] as num).toDouble()),
      );
}

/// Then/Now: where the historical photo's camera pointed (spec F-14).
class CaptureAngle {
  const CaptureAngle({required this.heading, required this.pitch});

  final double heading;
  final double pitch;

  static CaptureAngle? fromJson(Object? v) {
    if (v is! Map<String, dynamic> || v['captureHeading'] == null) return null;
    return CaptureAngle(
      heading: (v['captureHeading'] as num).toDouble(),
      pitch: (v['capturePitch'] as num?)?.toDouble() ?? 0,
    );
  }
}

class NowPhoto {
  const NowPhoto({
    required this.id,
    required this.createdAt,
    this.url,
    this.bytes,
    this.authorHandle,
    this.mine = false,
    this.pending = false,
  });

  final String id;
  final String? url;

  /// Demo mode / just taken: the photo has not left the device.
  final Uint8List? bytes;
  final DateTime createdAt;
  final String? authorHandle;
  final bool mine;
  final bool pending;

  factory NowPhoto.fromJson(Map<String, dynamic> j) => NowPhoto(
        id: j['id'] as String,
        url: j['url'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        authorHandle: j['authorHandle'] as String?,
        mine: j['mine'] as bool? ?? false,
        pending: j['pending'] as bool? ?? false,
      );
}

/// Smallest signed difference between two compass headings, -180…180.
double headingDelta(double target, double current) => ((target - current + 540) % 360) - 180;
