import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trace/core/api/api_error.dart';
import 'package:trace/core/api/conditions.dart';
import 'package:trace/core/api/demo_api.dart';
import 'package:trace/core/api/geo.dart';
import 'package:trace/core/api/models.dart';
import 'package:trace/core/api/sun.dart';
import 'package:trace/core/format.dart';
import 'package:trace/features/compass/hot_cold.dart';

void main() {
  group('format', () {
    final now = DateTime(2026, 10, 4, 12);

    test('timeAgo', () {
      expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(timeAgo(now.subtract(const Duration(days: 1)), now: now), 'yesterday');
      expect(timeAgo(now.subtract(const Duration(days: 9)), now: now), '9 days ago');
    });

    test('distanceLabel', () {
      expect(distanceLabel(243), '240 m');
      expect(distanceLabel(1530), '1.5 km');
      expect(distanceLabel(12400), '12 km');
    });
  });

  group('geo', () {
    test('unlock radius mirrors the server', () {
      expect(unlockRadius(0), 40);
      expect(unlockRadius(18), 58);
      expect(unlockRadius(500), 80);
    });

    test('fuzzy circle is deterministic and contains the true point', () {
      const p = LatLng(31.5204, 74.3587);
      for (var i = 0; i < 200; i++) {
        final a = fuzzyCircle('drop-$i', p);
        expect(fuzzyCircle('drop-$i', p).center, a.center);
        final d = metersBetween(a.center, p);
        expect(d, inInclusiveRange(39.5, 120.5));
        expect(d, lessThan(a.radius));
      }
    });
  });

  test('every unlock failure has a human message', () {
    for (final code in ['too_far', 'low_accuracy', 'stale', 'suspicious', 'condition_locked', 'capsule_locked', 'not_visible']) {
      expect(ApiError(code).message, isNot(contains('Something went wrong')));
    }
  });

  group('DemoApi', () {
    const here = LatLng(31.5204, 74.3587);

    LocationFix fixAt(LatLng p) => LocationFix(lat: p.latitude, lng: p.longitude, accuracy: 8, timestamp: DateTime.now());

    test('seeds drops and enforces distance on unlock', () async {
      final api = DemoApi();
      final drops = await api.nearby(here.latitude, here.longitude);
      expect(drops, isNotEmpty);

      final far = drops.firstWhere((d) => d.teaser == 'Exam week survival kit.');
      expect(() => api.unlock(far.id, fixAt(here)), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'too_far')));

      final there = api.truePointOf(far.id)!;
      final content = await api.unlock(far.id, fixAt(there));
      expect(content.body, contains('vending machine'));
      expect((await api.passport()).unlocked.single.id, far.id);
    });

    test('conditional drops stay locked until their moment', () async {
      final api = DemoApi();
      final drops = await api.nearby(here.latitude, here.longitude);
      // Demo weather is always clear, so the rain drop never opens.
      final rain = drops.firstWhere((d) => d.conditionKinds.contains('weather'));
      expect(rain.conditions, isNull, reason: 'its rule is not revealed');
      expect(
        () => api.unlock(rain.id, fixAt(api.truePointOf(rain.id)!)),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'condition_locked')),
      );
      final night = drops.firstWhere((d) => d.conditionKinds.contains('night'));
      expect(night.conditions, isNotNull, reason: 'its rule is revealed');
    });

    test('sealed capsules stay locked', () async {
      final api = DemoApi();
      final drops = await api.nearby(here.latitude, here.longitude);
      final capsule = drops.firstWhere((d) => d.forYou);
      expect(capsule.isSealed, isTrue);
      expect(
        () => api.unlock(capsule.id, fixAt(api.truePointOf(capsule.id)!)),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'capsule_locked')),
      );
    });

    test('near hint only within 100 m', () async {
      final api = DemoApi();
      final drops = await api.nearby(here.latitude, here.longitude);
      final far = drops.firstWhere((d) => d.teaser == 'Exam week survival kit.');
      expect(() => api.nearHint(far.id, fixAt(here)), throwsA(isA<ApiError>()));
      final truth = api.truePointOf(far.id)!;
      final hint = await api.nearHint(far.id, fixAt(offsetBy(truth, 0, 60)));
      expect(hint.point, truth);
      expect(hint.isValid, isTrue);
    });

    test('rejects capsules sealed for less than a day', () async {
      final api = DemoApi();
      await api.nearby(here.latitude, here.longitude);
      expect(
        () => api.createDrop(
          type: DropType.text,
          fix: fixAt(here),
          body: 'hi',
          unlockAt: DateTime.now().add(const Duration(hours: 2)),
        ),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'capsule_too_soon')),
      );
    });
  });

group('sun', () {
  // The server's suncalc 2.x uses refined Meeus series; this classic port (demo mode only)
  // stays within a few minutes, well inside the 45-minute sun windows.
  test('matches suncalc on the server to within 3 minutes', () {
    final t = SunTimes.of(DateTime.utc(2026, 10, 4, 7), 31.5204, 74.3587);
    void near(DateTime? actual, String expected) =>
        expect(actual!.difference(DateTime.parse(expected)).inSeconds.abs(), lessThan(180));
    near(t.sunrise, '2026-10-04T00:58:02.737Z');
    near(t.sunset, '2026-10-04T12:44:11.849Z');
    near(t.dawn, '2026-10-04T00:33:45.283Z');
    near(t.dusk, '2026-10-04T13:08:27.708Z');
    near(t.goldenHour, '2026-10-04T12:11:55.491Z');
    near(t.goldenHourEnd, '2026-10-04T01:30:20.835Z');
  });

  test('polar night has no sunset', () {
    expect(SunTimes.of(DateTime.utc(2026, 12, 21, 12), 85, 0).sunset, isNull);
  });
});

group('hot/cold', () {
  test('pulse interval spans 2 s to 0.15 s and shrinks as you close in', () {
    expect(pulseInterval(400), const Duration(milliseconds: 2000));
    expect(pulseInterval(300), const Duration(milliseconds: 2000));
    expect(pulseInterval(10), const Duration(milliseconds: 150));
    expect(pulseInterval(100) < pulseInterval(200), isTrue);
    expect(pulseInterval(30) < pulseInterval(100), isTrue);
  });

  test('alignment is 1 dead ahead and 0 behind', () {
    expect(alignment(0), closeTo(1, 1e-9));
    expect(alignment(180), closeTo(0, 1e-9));
    expect(alignment(90), closeTo(0.5, 1e-9));
    expect(alignment(null), isNull);
  });
});

test('conditions read naturally', () {
  expect(
    describeConditions(const [SunCondition(SunPhase.sunset), WeatherCondition(WeatherKind.rain)]),
    'around sunset and when it’s raining',
  );
  expect(
    describeConditions(const [
      SunCondition(SunPhase.night),
      WeatherCondition(WeatherKind.fog),
      TimeRangeCondition('20:00', '04:00', 'Asia/Karachi'),
    ]),
    'at night, in the fog and between 20:00 and 04:00',
  );
  final json = const TimeRangeCondition('20:00', '04:00', 'Asia/Karachi').toJson();
  expect(DropCondition.fromJson(json), isA<TimeRangeCondition>());
});
}
