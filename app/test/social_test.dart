import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:trace/core/api/api_error.dart';
import 'package:trace/core/api/demo_api.dart';
import 'package:trace/core/api/geo.dart';
import 'package:trace/core/api/models.dart';

const here = LatLng(31.5204, 74.3587);

LocationFix fixAt(LatLng p) => LocationFix(lat: p.latitude, lng: p.longitude, accuracy: 8, timestamp: DateTime.now());

Matcher failsWith(String code) => throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

Future<(DemoApi, List<NearbyDrop>)> seeded() async {
  final api = DemoApi();
  await api.setHandle('explorer');
  return (api, await api.nearby(here.latitude, here.longitude));
}

Future<List<String>> visibleIds(DemoApi api) async => [for (final d in await api.nearby(here.latitude, here.longitude)) d.id];

void main() {
  group('trails', () {
    test('later stops stay hidden and locked until the previous one is found', () async {
      final (api, drops) = await seeded();
      final stop1 = drops.firstWhere((d) => d.trail?.seq == 1);
      expect(stop1.trail!.total, 3);
      expect(drops.where((d) => d.trail != null).length, 1, reason: 'only stop 1 is on the map');

      expect(() => api.unlock('trail-b', fixAt(api.truePointOf('trail-b')!)), failsWith('trail_order'));

      final opened = await api.unlock(stop1.id, fixAt(api.truePointOf(stop1.id)!));
      expect(opened.trail!.nextClue, contains('oldest door'));
      expect(await visibleIds(api), contains('trail-b'));
    });

    test('finishing every stop awards a stamp', () async {
      final (api, _) = await seeded();
      for (final id in ['trail-a', 'trail-b', 'trail-c']) {
        await api.unlock(id, fixAt(api.truePointOf(id)!));
      }
      final trail = await api.trail('trail-old-city');
      expect(trail.found, 3);
      expect(trail.completedAt, isNotNull);
      expect((await api.passport()).stamps.single.title, 'Old City Hunt');
    });

    test('trail page reveals clues one stop at a time', () async {
      final (api, _) = await seeded();
      final t = await api.trail('trail-old-city');
      expect(t.stops[0].clue, isNotNull);
      expect(t.stops[1].clue, isNull);
      expect(t.stops[1].reached, isFalse);
      expect(t.current?.seq, 1);
    });

    test('a trail needs at least three of your own drops', () async {
      final (api, _) = await seeded();
      expect(() => api.createTrail('Mine', [(dropId: 'seed-0', clue: null)]), failsWith('invalid_stops'));
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add(await api.createDrop(type: DropType.text, fix: fixAt(offsetBy(here, i * 120.0, 300)), body: 'stop $i'));
      }
      final id = await api.createTrail('My walk', [for (final d in ids) (dropId: d, clue: 'clue for $d')]);
      expect((await api.trail(id)).mine, isTrue);
    });
  });

  group('circles', () {
    test('circle drops only show for members', () async {
      final (api, drops) = await seeded();
      expect(drops.firstWhere((d) => d.id == 'circle-a').circle!.name, 'Hostel 4 crew');
      await api.leaveCircle('circle-hostel');
      expect(await visibleIds(api), isNot(contains('circle-a')));
    });

    test('join with a code, however it is typed', () async {
      final (api, _) = await seeded();
      expect(() => api.joinCircle('NOPE1234'), failsWith('invalid_code'));
      final c = await api.joinCircle(' wander-29 ');
      expect(c.name, 'Saturday walkers');
      expect((await api.circles()).map((c) => c.id), contains('circle-walkers'));
    });

    test('owners cannot leave; creating a circle makes you the owner', () async {
      final (api, _) = await seeded();
      final mine = await api.createCircle('Book club');
      expect(mine.isOwner, isTrue);
      expect(mine.inviteCode, matches(RegExp(r'^[2-9A-HJKMNP-Z]{8}$')));
      expect(() => api.leaveCircle(mine.id), failsWith('owner_cannot_leave'));
    });

    test('circle and recipients are exclusive', () async {
      final (api, _) = await seeded();
      expect(
        () => api.createDrop(
          type: DropType.text,
          fix: fixAt(here),
          body: 'x',
          circleId: 'circle-hostel',
          recipientHandles: const ['noor'],
          unlockAt: DateTime.now().add(const Duration(days: 2)),
        ),
        failsWith('visibility_conflict'),
      );
    });
  });

  group('echoes', () {
    test('need an unlock and being there', () async {
      final (api, _) = await seeded();
      final truth = api.truePointOf('seed-0')!;
      expect(() => api.echoes('seed-0'), failsWith('locked'));

      await api.unlock('seed-0', fixAt(truth));
      expect((await api.echoes('seed-0')).length, 3);

      expect(() => api.postEcho('seed-0', 'hello', fixAt(offsetBy(truth, 0, 500))), failsWith('too_far'));
      final echo = await api.postEcho('seed-0', 'hello from here', fixAt(truth));
      expect(echo.pending, isTrue);
      expect((await api.echoes('seed-0')).last.body, 'hello from here');
    });
  });
}
