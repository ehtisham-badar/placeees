import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trace/core/api/api_error.dart';
import 'package:trace/core/api/demo_api.dart';
import 'package:trace/core/api/geo.dart';
import 'package:trace/core/api/models.dart';
import 'package:trace/core/format.dart';

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

    test('conditional drops stay locked', () async {
      final api = DemoApi();
      final drops = await api.nearby(here.latitude, here.longitude);
      final night = drops.firstWhere((d) => d.hasCondition);
      expect(
        () => api.unlock(night.id, fixAt(api.truePointOf(night.id)!)),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'condition_locked')),
      );
    });
  });
}
