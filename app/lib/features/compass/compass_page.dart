import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/demo_api.dart';
import '../../core/api/geo.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/analytics.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../unlock/unlock_page.dart';
import 'hot_cold.dart';

const _cold = Color(0xFF6E8BFF);

Color heatColor(double h) => h < 0.5
    ? Color.lerp(_cold, TraceColors.ember, h * 2)!
    : Color.lerp(TraceColors.ember, TraceColors.sun, (h - 0.5) * 2)!;

/// Hot/cold hunt for one drop (spec F-07). Steers toward the fuzzy centre until within 100 m,
/// then the server reveals the true point for a few minutes.
class CompassPage extends StatefulWidget {
  const CompassPage({super.key, required this.drop, this.onUnlocked});

  final NearbyDrop drop;
  final ValueChanged<String>? onUnlocked;

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> with SingleTickerProviderStateMixin {
  static const _distance = Distance();

  late final LocationService _location = context.read<LocationService>();
  late final TraceApi _api = context.read<TraceApi>();
  late final _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final HotColdEngine _engine = HotColdEngine(
    distance: () => _meters,
    facing: () => alignment(_relative),
    onPulse: () => _beat.forward(from: 0),
  );

  StreamSubscription<CompassEvent>? _compass;
  double? _heading;
  NearHint? _hint;
  DateTime? _lastHintTry;
  double? _trendFrom;
  int _trend = 0; // -1 warmer, 1 colder

  @override
  void initState() {
    super.initState();
    _compass = FlutterCompass.events?.listen((e) {
      if (mounted && e.heading != null) setState(() => _heading = e.heading);
    });
    _location.addListener(_onFix);
    _onFix();
    _engine.start();
    context.read<Analytics>().track('compass_start', {'dropId': widget.drop.id});
  }

  @override
  void dispose() {
    _engine.stop();
    _compass?.cancel();
    _location.removeListener(_onFix);
    _beat.dispose();
    super.dispose();
  }

  LatLng? get _here => _location.fix?.point;
  bool get _locked => _hint?.isValid ?? false;
  LatLng get _target => _locked ? _hint!.point : widget.drop.center;
  double? get _meters => _here == null ? null : metersBetween(_here!, _target);

  double? get _bearing {
    final here = _here;
    if (here == null) return null;
    return (_distance.bearing(here, _target) + 360) % 360;
  }

  /// Target bearing relative to where the phone points, -180…180. Null without a compass.
  double? get _relative {
    final b = _bearing;
    final h = _heading;
    if (b == null || h == null) return null;
    return ((b - h + 540) % 360) - 180;
  }

  void _onFix() {
    if (!mounted) return;
    final m = _meters;
    if (m != null) {
      // Only count moves of 4 m+ so GPS jitter doesn't flip the trend.
      if (_trendFrom == null || (m - _trendFrom!).abs() >= 4) {
        if (_trendFrom != null) _trend = m < _trendFrom! ? -1 : 1;
        _trendFrom = m;
      }
      _maybeAskForHint();
    }
    setState(() {});
  }

  /// Within reach of the true point (fuzz ≤ 120 m + 100 m), ask the server for it every ~10 s.
  Future<void> _maybeAskForHint() async {
    if (_locked || _here == null) return;
    if (metersBetween(_here!, widget.drop.center) > 220) return;
    final now = DateTime.now();
    if (_lastHintTry != null && now.difference(_lastHintTry!) < const Duration(seconds: 10)) return;
    _lastHintTry = now;
    final fix = await _location.freshFix(maxAge: const Duration(seconds: 5));
    if (fix == null) return;
    try {
      final hint = await _api.nearHint(widget.drop.id, fix);
      if (!mounted) return;
      setState(() {
        _hint = hint;
        _trendFrom = null;
        _trend = 0;
      });
    } on ApiError {
      // Not close enough yet; keep steering by the glow.
    }
  }

  void _unlock() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: Motion.slow,
        pageBuilder: (_, _, _) => UnlockPage(drop: widget.drop, onUnlocked: widget.onUnlocked),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _demoStep() {
    final api = _api;
    final here = _here;
    if (api is! DemoApi || here == null) return;
    final truth = api.truePointOf(widget.drop.id) ?? _target;
    final d = metersBetween(here, truth);
    final b = _distance.bearing(here, truth);
    _location.simulateAt(offsetBy(here, b, math.min(25, math.max(0, d - 6))));
  }

  @override
  Widget build(BuildContext context) {
    final m = _meters;
    final h = heat(m);
    final color = heatColor(h);
    final accuracy = _location.fix?.accuracy ?? 20;
    final canUnlock = m != null && (_locked ? m <= unlockRadius(accuracy) + 10 : m <= widget.drop.radius * 0.35);
    final word = switch (m) {
      null => 'Finding you…',
      > 250 => 'Cold',
      > 150 => 'Cool',
      > 80 => 'Warm',
      > 30 => 'Hot',
      _ => 'Burning',
    };

    return Scaffold(
      body: Stack(
        children: [
          // Background glow grows with heat.
          Positioned.fill(
            child: AnimatedContainer(
              duration: Motion.slow,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.6 + 0.6 * h,
                  colors: [color.withValues(alpha: 0.10 + 0.22 * h), TraceColors.ink],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(
                children: [
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Stop hunting'),
                      const SizedBox(width: Space.sm + 4),
                      Expanded(
                        child: Text(
                          widget.drop.teaser ?? 'Somewhere close…',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: serif(size: 18, style: FontStyle.italic, color: TraceColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox.square(
                    dimension: 300,
                    child: AnimatedBuilder(
                      animation: _beat,
                      builder: (_, _) => CustomPaint(
                        painter: _DialPainter(
                          relative: _relative,
                          absolute: _bearing,
                          heading: _heading,
                          color: color,
                          beat: _beat.value,
                          heat: h,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Text(
                      key: ValueKey(word),
                      word,
                      style: serif(size: 44, weight: FontWeight.w600, color: color, height: 1),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        m == null ? '' : '${_locked ? '' : '≈ '}${distanceLabel(m)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      if (_trend != 0) ...[
                        const SizedBox(width: Space.sm),
                        Icon(
                          _trend < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                          size: 20,
                          color: _trend < 0 ? TraceColors.sun : _cold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _trend < 0 ? 'warmer' : 'colder',
                          style: TextStyle(color: _trend < 0 ? TraceColors.sun : _cold, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    _locked
                        ? 'Locked on. The exact spot is yours for a few minutes.'
                        : _heading == null
                            ? 'No compass on this device. The arrow points north-up.'
                            : 'Follow the pulse. It quickens as you close in.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: Motion.medium,
                    child: canUnlock
                        ? PrimaryButton(
                            key: const ValueKey('unlock'),
                            label: "You're here. Unlock",
                            icon: Icons.lock_open_rounded,
                            onPressed: _unlock,
                          )
                        : const SizedBox(key: ValueKey('none'), height: 58),
                  ),
                  if (AppConfig.isDemo && _api is DemoApi)
                    TextButton.icon(
                      onPressed: _demoStep,
                      icon: const Icon(Icons.directions_walk_rounded, size: 18, color: TraceColors.textMuted),
                      label: const Text('Demo: take a few steps', style: TextStyle(color: TraceColors.textMuted)),
                    ),
                  const SizedBox(height: Space.sm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.relative,
    required this.absolute,
    required this.heading,
    required this.color,
    required this.beat,
    required this.heat,
  });

  /// Target relative to the phone's heading; drives the needle when a compass exists.
  final double? relative;

  /// Target bearing from north; used north-up when there's no compass.
  final double? absolute;
  final double? heading;
  final Color color;
  final double beat;
  final double heat;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Beat ring, in time with the haptic pulse.
    if (beat > 0 && beat < 1) {
      final e = Curves.easeOutCubic.transform(beat);
      canvas.drawCircle(
        c,
        r * (0.45 + 0.55 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.6 * (1 - beat)),
      );
    }

    // Outer ring and ticks, rotated so north stays north.
    final north = heading == null ? 0.0 : -heading! * math.pi / 180;
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = TraceColors.line,
    );
    for (var i = 0; i < 72; i++) {
      final a = north + i * math.pi / 36 - math.pi / 2;
      final long = i % 18 == 0;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * r * (long ? 0.80 : 0.85),
        c + dir * r * 0.9,
        Paint()
          ..strokeWidth = long ? 2 : 1
          ..strokeCap = StrokeCap.round
          ..color = (i == 0 ? TraceColors.rose : TraceColors.textFaint).withValues(alpha: long ? 0.9 : 0.5),
      );
    }

    // Core glow.
    canvas.drawCircle(
      c,
      r * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.35 + 0.3 * heat), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.42)),
    );

    // Needle toward the target.
    final deg = relative ?? (absolute == null ? null : absolute! + (heading == null ? 0 : -heading!));
    if (deg != null) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(deg * math.pi / 180);
      final needle = Path()
        ..moveTo(0, -r * 0.74)
        ..lineTo(r * 0.09, -r * 0.18)
        ..lineTo(0, -r * 0.24)
        ..lineTo(-r * 0.09, -r * 0.18)
        ..close();
      canvas.drawPath(needle, Paint()..color = color.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      canvas.drawPath(needle, Paint()..color = color);
      canvas.restore();
    }

    canvas.drawCircle(c, 9, Paint()..color = TraceColors.text);
    canvas.drawCircle(c, 9, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = TraceColors.ink);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.relative != relative ||
      old.absolute != absolute ||
      old.heading != heading ||
      old.color != color ||
      old.beat != beat ||
      old.heat != heat;
}
