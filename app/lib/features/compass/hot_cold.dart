import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

const compassMaxRange = 300.0;

/// Pulse interval per spec F-07: 2.0 s at 300 m down to 0.15 s under 20 m, on a log curve so
/// the change feels even as you walk.
Duration pulseInterval(double meters) {
  if (meters <= 20) return const Duration(milliseconds: 150);
  if (meters >= compassMaxRange) return const Duration(milliseconds: 2000);
  final t = math.log(meters / 20) / math.log(compassMaxRange / 20);
  return Duration(milliseconds: (150 + t * (2000 - 150)).round());
}

/// 0 when far or unknown, 1 when on top of it.
double heat(double? meters) => meters == null ? 0 : (1 - (meters.clamp(0, compassMaxRange) / compassMaxRange)).toDouble();

/// How well you're facing the target, 0 (behind) to 1 (dead ahead). Null without a compass.
double? alignment(double? relativeDegrees) =>
    relativeDegrees == null ? null : (1 + math.cos(relativeDegrees * math.pi / 180)) / 2;

/// Drives haptic pulses: faster when closer, stronger when facing the target.
class HotColdEngine {
  HotColdEngine({required this.distance, required this.facing, this.onPulse});

  /// Current distance to target in meters, or null if unknown.
  final double? Function() distance;

  /// Current alignment (see [alignment]), or null without a compass.
  final double? Function() facing;

  /// Called on every pulse, for a matching visual beat.
  final void Function()? onPulse;

  Timer? _timer;

  void start() {
    stop();
    _schedule();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule() {
    final d = distance();
    _timer = Timer(d == null ? const Duration(seconds: 2) : pulseInterval(d), () {
      if (distance() != null) _pulse();
      _schedule();
    });
  }

  void _pulse() {
    final a = facing();
    // Without a compass, distance alone sets the strength.
    final strength = a ?? heat(distance());
    if (strength > 0.85) {
      HapticFeedback.heavyImpact();
    } else if (strength > 0.5) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    onPulse?.call();
  }
}
