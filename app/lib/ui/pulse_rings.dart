import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// Soft concentric rings radiating from a point: the visual signature of a drop.
class PulseRings extends StatefulWidget {
  const PulseRings({
    super.key,
    this.size = 260,
    this.color = TraceColors.ember,
    this.rings = 3,
    this.period = const Duration(milliseconds: 3200),
    this.child,
  });

  final double size;
  final Color color;
  final int rings;
  final Duration period;
  final Widget? child;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RingsPainter(_c, widget.color, widget.rings),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color, this.rings) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;
    for (var i = 0; i < rings; i++) {
      final p = (t.value + i / rings) % 1.0;
      final eased = Curves.easeOutCubic.transform(p);
      final opacity = math.pow(1 - p, 1.6).toDouble();
      canvas.drawCircle(
        center,
        maxR * (0.12 + 0.88 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.55 * opacity),
      );
      canvas.drawCircle(
        center,
        maxR * (0.12 + 0.88 * eased),
        Paint()..color = color.withValues(alpha: 0.05 * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.color != color || old.rings != rings;
}

/// The glowing core dot at the centre of rings and map markers.
class EmberDot extends StatelessWidget {
  const EmberDot({super.key, this.size = 18, this.color = TraceColors.ember});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Color.lerp(color, Colors.white, 0.45)!, color]),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: size, spreadRadius: size * 0.1)],
      ),
    );
  }
}
