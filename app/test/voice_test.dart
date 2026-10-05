import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:trace/core/api/api_error.dart';
import 'package:trace/core/api/demo_api.dart';
import 'package:trace/core/api/models.dart';
import 'package:trace/features/voice/waveform.dart';

void main() {
  test('mic levels map to 0..1 bars', () {
    expect(levelFromDb(-160), 0);
    expect(levelFromDb(-25), 0.5);
    expect(levelFromDb(0), 1);
  });

  test('downsampling keeps the shape and normalises to the loudest', () {
    final samples = [for (var i = 0; i < 200; i++) i < 100 ? 0.2 : 0.8];
    final bars = downsample(samples, 10);
    expect(bars, hasLength(10));
    expect(bars.last, 1.0);
    expect(bars.first, closeTo(0.25, 0.01));
    expect(downsample(const [], 8), everyElement(0.05));
  });

  test('clock formats like a player', () {
    expect(clock(const Duration(seconds: 7)), '0:07');
    expect(clock(const Duration(seconds: 30)), '0:30');
  });

  test('demo voice drops need audio and keep their waveform', () async {
    final api = DemoApi();
    const here = LatLng(31.52, 74.35);
    final fix = LocationFix(lat: here.latitude, lng: here.longitude, accuracy: 8, timestamp: DateTime.now());
    await api.nearby(here.latitude, here.longitude);
    await expectLater(api.createDrop(type: DropType.voice, fix: fix), throwsA(isA<ApiError>()));
    final id = await api.createDrop(
      type: DropType.voice,
      fix: fix,
      voiceAac: Uint8List.fromList([1, 2, 3]),
      waveform: List.filled(48, 0.5),
    );
    final c = await api.drop(id);
    expect(c.type, DropType.voice);
    expect(c.waveform, hasLength(48));
    expect(c.localAudio, isNotNull);
  });
}
