import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Serif voice for anything people wrote: drop text, teasers, big titles.
TextStyle serif({double size = 20, FontWeight weight = FontWeight.w400, FontStyle? style, Color? color, double? height}) =>
    GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: weight,
      fontStyle: style,
      color: color ?? TraceColors.text,
      height: height ?? 1.25,
    );

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(
    bodyColor: TraceColors.text,
    displayColor: TraceColors.text,
  );

  return base.copyWith(
    scaffoldBackgroundColor: TraceColors.ink,
    colorScheme: const ColorScheme.dark(
      primary: TraceColors.ember,
      secondary: TraceColors.mint,
      surface: TraceColors.surface,
      error: TraceColors.rose,
      onPrimary: TraceColors.ink,
      onSurface: TraceColors.text,
    ),
    textTheme: text.copyWith(
      headlineLarge: serif(size: 34, weight: FontWeight.w500, height: 1.1),
      headlineMedium: serif(size: 28, weight: FontWeight.w500, height: 1.15),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(color: TraceColors.textMuted, height: 1.45),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    ),
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TraceColors.surfaceHigh,
      hintStyle: const TextStyle(color: TraceColors.textFaint),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: TraceColors.ember, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: TraceColors.surfaceHigh,
      contentTextStyle: GoogleFonts.manrope(color: TraceColors.text, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, elevation: 0),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
