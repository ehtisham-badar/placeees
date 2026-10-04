import 'package:intl/intl.dart';

enum SunPhase {
  sunrise('around sunrise'),
  goldenHour('during golden hour'),
  sunset('around sunset'),
  night('at night');

  const SunPhase(this.phrase);
  final String phrase;
}

enum WeatherKind {
  rain('when it’s raining'),
  clear('under a clear sky'),
  cloudy('when it’s cloudy'),
  fog('in the fog'),
  snow('when it snows');

  const WeatherKind(this.phrase);
  final String phrase;
}

/// One rule a conditional drop waits for (spec F-08). Mirrors the API schema.
sealed class DropCondition {
  const DropCondition();

  Map<String, dynamic> toJson();

  /// Reads naturally after "Opens …".
  String get phrase;

  static DropCondition? fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'sun' => SunCondition(
            SunPhase.values.byName(j['phase'] as String),
            windowMinutes: (j['windowMinutes'] as num?)?.toInt() ?? 45,
          ),
        'weather' => WeatherCondition(WeatherKind.values.byName(j['is'] as String)),
        'timeRange' => TimeRangeCondition(j['from'] as String, j['to'] as String, j['tz'] as String),
        'dateRange' => DateRangeCondition(
            DateTime.parse(j['from'] as String),
            DateTime.parse(j['to'] as String),
            j['tz'] as String,
          ),
        _ => null,
      };
}

class SunCondition extends DropCondition {
  const SunCondition(this.phase, {this.windowMinutes = 45});

  final SunPhase phase;
  final int windowMinutes;

  @override
  Map<String, dynamic> toJson() => {'type': 'sun', 'phase': phase.name, 'windowMinutes': windowMinutes};

  @override
  String get phrase => phase.phrase;
}

class WeatherCondition extends DropCondition {
  const WeatherCondition(this.kind);

  final WeatherKind kind;

  @override
  Map<String, dynamic> toJson() => {'type': 'weather', 'is': kind.name};

  @override
  String get phrase => kind.phrase;
}

/// `from`/`to` are "HH:mm"; a window where from > to runs past midnight.
class TimeRangeCondition extends DropCondition {
  const TimeRangeCondition(this.from, this.to, this.tz);

  final String from;
  final String to;
  final String tz;

  @override
  Map<String, dynamic> toJson() => {'type': 'timeRange', 'from': from, 'to': to, 'tz': tz};

  @override
  String get phrase => 'between $from and $to';
}

class DateRangeCondition extends DropCondition {
  const DateRangeCondition(this.from, this.to, this.tz);

  final DateTime from;
  final DateTime to;
  final String tz;

  static final _ymd = DateFormat('yyyy-MM-dd');
  static final _short = DateFormat.MMMd();

  @override
  Map<String, dynamic> toJson() => {'type': 'dateRange', 'from': _ymd.format(from), 'to': _ymd.format(to), 'tz': tz};

  @override
  String get phrase => from == to ? 'on ${_short.format(from)}' : 'from ${_short.format(from)} to ${_short.format(to)}';
}

/// "around sunset, when it’s raining and between 20:00 and 04:00"
String describeConditions(List<DropCondition> all) {
  final parts = all.map((c) => c.phrase).toList();
  if (parts.length <= 1) return parts.join();
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}
