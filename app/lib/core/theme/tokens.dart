import 'package:flutter/material.dart';

/// Trace design tokens. Dark-first: the app lives on a night map.
abstract final class TraceColors {
  static const ink = Color(0xFF0A0C11);
  static const surface = Color(0xFF13161E);
  static const surfaceHigh = Color(0xFF1C202B);
  static const line = Color(0x1FFFFFFF);

  static const text = Color(0xFFF4F1EA);
  static const textMuted = Color(0xFF9097A6);
  static const textFaint = Color(0xFF5C6273);

  /// Primary: locked drops, calls to action.
  static const ember = Color(0xFFFF7A4D);
  static const sun = Color(0xFFFFB648);

  /// Unlocked / success.
  static const mint = Color(0xFF5FE3C3);

  /// Errors and warnings.
  static const rose = Color(0xFFFF5C7A);
  static const amber = Color(0xFFFFC857);

  static const emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ember, sun],
  );
}

abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class Radii {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 28.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}
