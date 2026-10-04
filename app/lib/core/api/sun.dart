import 'dart:math' as math;

/// Sunrise/sunset/dusk/dawn/golden hour for a day and place.
/// Classic suncalc algorithm, used by demo mode only. The API uses suncalc 2.x (refined Meeus
/// series); the two agree to within a couple of minutes, well inside the 45-minute sun windows.
class SunTimes {
  const SunTimes({
    this.sunrise,
    this.sunset,
    this.dawn,
    this.dusk,
    this.goldenHourEnd,
    this.goldenHour,
    required this.solarNoon,
  });

  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? dawn;
  final DateTime? dusk;
  final DateTime? goldenHourEnd;
  final DateTime? goldenHour;
  final DateTime solarNoon;

  static const _rad = math.pi / 180;
  static const _dayMs = 86400000;
  static const _j1970 = 2440588;
  static const _j2000 = 2451545;
  static const _j0 = 0.0009;
  static const _e = _rad * 23.4397;

  static SunTimes of(DateTime date, double lat, double lng) {
    final lw = _rad * -lng;
    final phi = _rad * lat;
    final d = date.millisecondsSinceEpoch / _dayMs - 0.5 + _j1970 - _j2000;
    final n = (d - _j0 - lw / (2 * math.pi)).roundToDouble();
    final ds = _j0 + lw / (2 * math.pi) + n;
    final m = _rad * (357.5291 + 0.98560028 * ds);
    final c = _rad * (1.9148 * math.sin(m) + 0.02 * math.sin(2 * m) + 0.0003 * math.sin(3 * m));
    final l = m + c + _rad * 102.9372 + math.pi;
    final dec = math.asin(math.sin(l) * math.sin(_e));
    double transit(double j) => _j2000 + j + 0.0053 * math.sin(m) - 0.0069 * math.sin(2 * l);
    final noon = transit(ds);

    DateTime from(double j) => DateTime.fromMillisecondsSinceEpoch(((j + 0.5 - _j1970) * _dayMs).round(), isUtc: true);

    (DateTime?, DateTime?) pair(double angle) {
      final cosW = (math.sin(angle * _rad) - math.sin(phi) * math.sin(dec)) / (math.cos(phi) * math.cos(dec));
      if (cosW.abs() > 1) return (null, null); // the sun never reaches this angle today
      final w = math.acos(cosW);
      final set = transit(_j0 + (w + lw) / (2 * math.pi) + n);
      return (from(noon - (set - noon)), from(set));
    }

    final (sunrise, sunset) = pair(-0.833);
    final (dawn, dusk) = pair(-6);
    final (goldenHourEnd, goldenHour) = pair(6);
    return SunTimes(
      sunrise: sunrise,
      sunset: sunset,
      dawn: dawn,
      dusk: dusk,
      goldenHourEnd: goldenHourEnd,
      goldenHour: goldenHour,
      solarNoon: from(noon),
    );
  }
}
