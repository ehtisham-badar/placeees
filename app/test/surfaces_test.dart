import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trace/core/alerts/nearby_alerts.dart';
import 'package:trace/core/api/demo_api.dart';
import 'package:trace/core/api/geo.dart';
import 'package:trace/core/api/models.dart';
import 'package:trace/core/integrity/integrity_service.dart';
import 'package:trace/core/push/push_service.dart';
import 'package:trace/core/widgets/home_summary.dart';
import 'package:trace/features/venues/venue_code.dart';

const here = LatLng(31.5204, 74.3587);

NearbyDrop drop(String id, double meters, {bool unlocked = false, bool pending = false, String? teaser}) => NearbyDrop(
      id: id,
      type: DropType.text,
      teaser: teaser,
      createdAt: DateTime(2026),
      center: offsetBy(here, 90, meters),
      radius: 150,
      mine: false,
      unlocked: unlocked,
      pending: pending,
    );

void main() {
  test('integrity client data matches the server format byte for byte', () {
    final fix = LocationFix(lat: 31.52, lng: 74.3587123, accuracy: 18, timestamp: DateTime.utc(2026, 10, 4, 14, 22, 11));
    expect(IntegrityService.clientData(fix), 'trace-loc-v1|31.520000|74.358712|18.0|2026-10-04T14:22:11.000Z');
    expect(fix.toJson()['timestamp'], '2026-10-04T14:22:11.000Z', reason: 'the signed and sent timestamps must match');
  });

  group('venue codes', () {
    test('come from links, web URLs and bare codes', () {
      expect(venueCodeFrom('trace://v/H7K2M9QX'), 'H7K2M9QX');
      expect(venueCodeFrom('https://trace.app/v/h7k2m9qx'), 'H7K2M9QX');
      expect(venueCodeFrom('https://trace.app/v/H7K2-M9QX?utm=poster'), 'H7K2M9QX');
      expect(venueCodeFrom(' h7k2 m9qx '), 'H7K2M9QX');
    });

    test('reject everything else', () {
      expect(venueCodeFrom('https://example.com/menu'), isNull);
      expect(venueCodeFrom('trace://v/'), isNull);
      expect(venueCodeFrom('HELLO1OO'), isNull, reason: '1 and O are not in the alphabet');
      expect(venueCodeFrom('https://trace.app/x/H7K2M9QX'), isNull);
    });

    test('the demo venue resolves', () async {
      final api = DemoApi();
      await api.nearby(here.latitude, here.longitude);
      expect(venueCodeFrom('trace://v/${DemoApi.demoVenueCode}'), DemoApi.demoVenueCode);
      final v = await api.venue(DemoApi.demoVenueCode);
      expect(v.drop.teaser, contains('chai'));
    });
  });

  group('nearby alerts', () {
    test('watch the nearest locked, live drops (max 20)', () {
      final drops = [
        drop('far', 900),
        drop('open', 50, unlocked: true),
        drop('review', 60, pending: true),
        drop('near', 100),
        for (var i = 0; i < 25; i++) drop('x$i', 200.0 + i),
      ];
      final picks = geofenceCandidates(drops, here);
      expect(picks.length, maxGeofences);
      expect(picks.first.id, 'near');
      expect(picks.map((d) => d.id), isNot(containsAll(['open', 'review', 'far'])));
    });

    test('at most 3 a day, never twice for the same drop within 24 h', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final t = DateTime(2026, 10, 5, 9);
      expect(await claimAlert(prefs, 'a', t), isTrue);
      expect(await claimAlert(prefs, 'a', t.add(const Duration(hours: 1))), isFalse);
      expect(await claimAlert(prefs, 'b', t), isTrue);
      expect(await claimAlert(prefs, 'c', t), isTrue);
      expect(await claimAlert(prefs, 'd', t), isFalse, reason: 'daily cap');
      expect(await claimAlert(prefs, 'd', t.add(const Duration(days: 1))), isTrue, reason: 'new day');
    });
  });

  test('widget summary counts locked drops within 500 m', () {
    final s = widgetSummary([
      drop('a', 300, teaser: 'Look up.'),
      drop('b', 600),
      drop('c', 700),
      drop('mine', 100, unlocked: true),
      drop('far', 2000),
    ], here);
    expect(s.count, 2); // circle edges: a 150 m, b 450 m (c's is 550 m)
    expect(s.teaser, 'Look up.');
    expect(s.distance, '150 m');
  });

  test('push stays off in demo mode, with no prompts', () async {
    final push = PushService(DemoApi(), openDrop: (_) {});
    expect(push.available, isFalse);
    expect(await push.enable(), isFalse);
    expect(await push.shouldSoftAsk(), isFalse);
  });
}
