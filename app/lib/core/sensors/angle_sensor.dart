import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Where the back camera points: compass heading (0–360) and pitch (-90 down … 90 up).
/// Used to save and match Then/Now angles (spec F-14).
class AngleSensor extends ChangeNotifier {
  double? heading;
  double? pitch;

  StreamSubscription<CompassEvent>? _compass;
  StreamSubscription<AccelerometerEvent>? _accel;

  bool get available => heading != null && pitch != null;

  void start() {
    _compass ??= FlutterCompass.events?.listen((e) {
      final h = e.headingForCameraMode ?? e.heading;
      if (h == null) return;
      heading = (h + 360) % 360;
      notifyListeners();
    });
    _accel ??= accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
      (e) {
        final g = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
        if (g < 1) return;
        // The back camera looks along -z; its elevation is asin(-z/|g|).
        final raw = math.asin((-e.z / g).clamp(-1.0, 1.0)) * 180 / math.pi;
        // Light smoothing so the guides don't jitter.
        pitch = pitch == null ? raw : pitch! * 0.8 + raw * 0.2;
        notifyListeners();
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _compass?.cancel();
    _accel?.cancel();
    super.dispose();
  }
}

String compassPoint(double heading) =>
    const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][((heading + 22.5) % 360 ~/ 45)];
