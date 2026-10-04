import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// A passport stamp for a completed trail: double ring, tilted, a little imperfect.
class TrailStamp extends StatelessWidget {
  const TrailStamp({super.key, required this.title, required this.date, this.size = 132, this.tilt = -0.14});

  final String title;
  final DateTime date;
  final double size;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    const color = TraceColors.mint;
    return Transform.rotate(
      angle: tilt,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _StampRings(color),
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.route_rounded, color: color, size: size * 0.16),
                const SizedBox(height: 2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: serif(size: size * 0.11, weight: FontWeight.w600, color: color, height: 1.05),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('d MMM yyyy').format(date).toUpperCase(),
                  style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: size * 0.065, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StampRings extends CustomPainter {
  _StampRings(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.9);
    canvas.drawCircle(c, r - 2, paint..strokeWidth = 2.2);
    canvas.drawCircle(c, r * 0.84, paint..strokeWidth = 1);
    // Small dots between the rings, like a rubber stamp's border.
    for (var i = 0; i < 28; i++) {
      final a = i / 28 * 2 * math.pi;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.92, 1.3, Paint()..color = color.withValues(alpha: 0.7));
    }
    canvas.drawCircle(c, r * 0.84, Paint()..color = color.withValues(alpha: 0.06));
  }

  @override
  bool shouldRepaint(_StampRings old) => old.color != color;
}
