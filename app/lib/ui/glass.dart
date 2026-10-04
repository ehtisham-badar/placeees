import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// Frosted panel that floats over the map.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = Radii.lg,
    this.padding = const EdgeInsets.all(Space.md),
    this.tint = 0.62,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double tint;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: TraceColors.surface.withValues(alpha: tint),
              borderRadius: shape,
              border: Border.all(color: TraceColors.line),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
