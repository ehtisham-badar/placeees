import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _distance = Distance();

double metersBetween(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

LatLng offsetBy(LatLng from, double bearingDeg, double meters) => _distance.offset(from, meters, bearingDeg);

/// Mirrors the server: unlock radius is 40 m + GPS accuracy, capped at 80 m.
double unlockRadius(double accuracy) => math.min(80, math.max(40, 40 + accuracy));

/// Deterministic fuzzy circle (40–120 m offset, 150 m radius), same contract as the API.
({LatLng center, double radius}) fuzzyCircle(String id, LatLng truePoint) {
  var h = 0x811c9dc5;
  for (final c in id.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  final u1 = (h & 0xffff) / 0xffff;
  final u2 = (h >> 16) / 0xffff;
  return (center: offsetBy(truePoint, u2 * 360, 40 + u1 * 80), radius: 150);
}
