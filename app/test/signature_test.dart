import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:trace/core/api/api_error.dart';
import 'package:trace/core/api/demo_api.dart';
import 'package:trace/core/api/geo.dart';
import 'package:trace/core/api/models.dart';
import 'package:trace/core/api/signature.dart';
import 'package:trace/core/sensors/angle_sensor.dart';

const here = LatLng(31.5204, 74.3587);

LocationFix fixAt(LatLng p) => LocationFix(lat: p.latitude, lng: p.longitude, accuracy: 8, timestamp: DateTime.now());

Matcher failsWith(String code) => throwsA(isA<ApiError>().having((e) => e.code, 'code', code));

Future<DemoApi> seeded() async {
  final api = DemoApi();
  await api.setHandle('explorer');
  await api.nearby(here.latitude, here.longitude);
  return api;
}

void main() {
  test('heading delta takes the short way round', () {
    expect(headingDelta(10, 350), 20);
    expect(headingDelta(350, 10), -20);
    expect(headingDelta(180, 0), -180);
    expect(compassPoint(135), 'SE');
    expect(compassPoint(359), 'N');
  });

  group('relays', () {
    test('open, pick up, carry 1 km, drop', () async {
      final api = await seeded();
      final start = api.truePointOf('relay-a')!;

      await expectLater(api.pickUpRelay('relay-a', fixAt(start)), failsWith('locked'));
      final opened = await api.unlock('relay-a', fixAt(start));
      expect(opened.relay!.canPickUp, isTrue);
      expect(opened.relay!.hops, 4);

      final deadline = await api.pickUpRelay('relay-a', fixAt(start));
      expect(deadline.difference(DateTime.now()).inDays, 6);
      expect((await api.carrying()).single.id, 'relay-a');
      final nearby = await api.nearby(here.latitude, here.longitude);
      expect(nearby.map((d) => d.id), isNot(contains('relay-a')), reason: 'carried relays leave the map');

      await expectLater(api.dropRelay('relay-a', fixAt(offsetBy(start, 0, 600))), failsWith('too_close'));
      final travelled = await api.dropRelay('relay-a', fixAt(offsetBy(start, 90, 1500)), note: 'Enjoy the view');
      expect(travelled, closeTo(1500, 5));
      expect(await api.carrying(), isEmpty);

      final journey = await api.relayJourney('relay-a');
      expect(journey.hops.length, 5);
      expect(journey.hops.last.handle, 'explorer');
      expect(journey.hops.last.note, 'Enjoy the view');
      expect(journey.path.length, 6);
    });

    test('nobody carries the same relay twice', () async {
      final api = await seeded();
      final start = api.truePointOf('relay-a')!;
      await api.unlock('relay-a', fixAt(start));
      await api.pickUpRelay('relay-a', fixAt(start));
      await api.dropRelay('relay-a', fixAt(offsetBy(start, 90, 1200)));
      await expectLater(api.pickUpRelay('relay-a', fixAt(api.truePointOf('relay-a')!)), failsWith('carried_before'));
    });

    test('your own relay is for others to carry', () async {
      final api = await seeded();
      final id = await api.createDrop(type: DropType.text, fix: fixAt(here), body: 'travel', isRelay: true);
      await expectLater(api.pickUpRelay(id, fixAt(here)), failsWith('own_relay'));
    });

    test('relays stay public', () async {
      final api = await seeded();
      await expectLater(api.createDrop(
          type: DropType.text,
          fix: fixAt(here),
          body: 'x',
          isRelay: true,
          unlockAt: DateTime.now().add(const Duration(days: 2)),
        ), failsWith('relay_must_be_public'),
      );
    });
  });

  group('then/now', () {
    test('needs a saved angle', () async {
      final api = await seeded();
      await expectLater(api.createDrop(type: DropType.thenNow, fix: fixAt(here), photoJpeg: Uint8List(4)), failsWith('angle_required'),
      );
      final id = await api.createDrop(
        type: DropType.thenNow,
        fix: fixAt(here),
        photoJpeg: Uint8List(4),
        angle: const CaptureAngle(heading: 90, pitch: 2),
      );
      expect((await api.drop(id)).angle!.heading, 90);
    });

    test('now photos are taken on the spot and join the timeline', () async {
      final api = await seeded();
      final spot = api.truePointOf('thennow-a')!;
      await expectLater(api.nowPhotos('thennow-a'), failsWith('locked'));

      final opened = await api.unlock('thennow-a', fixAt(spot));
      expect(opened.type, DropType.thenNow);
      expect(opened.angle!.heading, 135);
      expect((await api.nowPhotos('thennow-a')).length, 2);

      await expectLater(api.postNowPhoto('thennow-a', Uint8List(4), fixAt(offsetBy(spot, 0, 400))), failsWith('too_far'));
      await api.postNowPhoto('thennow-a', Uint8List(4), fixAt(spot), heading: 133, pitch: 3);
      final photos = await api.nowPhotos('thennow-a');
      expect(photos.length, 3);
      expect(photos.first.mine, isTrue);
    });

    test('drop type round-trips through the wire name', () {
      expect(DropType.parse('then_now'), DropType.thenNow);
      expect(DropType.thenNow.wire, 'then_now');
    });
  });
}
