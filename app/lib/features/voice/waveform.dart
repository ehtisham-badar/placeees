import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

const voiceMaxDuration = Duration(seconds: 30);
const waveformBars = 48;

/// Microphone level in dBFS (≈ -160…0) to a 0..1 bar height. Quiet rooms sit near the bottom.
double levelFromDb(double db) => ((db + 50) / 50).clamp(0.0, 1.0).toDouble();

/// Averages a recording's samples into a fixed number of bars, normalised so the loudest is 1.
List<double> downsample(List<double> samples, [int bars = waveformBars]) {
  if (samples.isEmpty) return List.filled(bars, 0.05);
  final out = List<double>.generate(bars, (i) {
    final from = (i * samples.length / bars).floor();
    final to = math.max(from + 1, ((i + 1) * samples.length / bars).floor());
    final slice = samples.sublist(from, math.min(to, samples.length));
    return slice.isEmpty ? 0 : slice.reduce((a, b) => a + b) / slice.length;
  });
  final peak = out.reduce(math.max);
  return [for (final v in out) peak <= 0 ? 0.05 : (v / peak).clamp(0.05, 1.0).toDouble()];
}

/// Rounded bars; the played part glows ember. Tap or drag to seek.
class WaveformBars extends StatelessWidget {
  const WaveformBars({super.key, required this.levels, this.progress = 0, this.onSeek, this.height = 56});

  final List<double> levels;

  /// 0..1 of the recording played so far.
  final double progress;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset local) => onSeek?.call((local.dx / constraints.maxWidth).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
          onHorizontalDragUpdate: onSeek == null ? null : (d) => seek(d.localPosition),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(painter: _BarsPainter(levels, progress)),
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.levels, this.progress);

  final List<double> levels;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final slot = size.width / levels.length;
    final w = math.max(2.0, slot * 0.55);
    for (var i = 0; i < levels.length; i++) {
      final h = math.max(4.0, levels[i] * size.height);
      final x = i * slot + (slot - w) / 2;
      final played = (i + 0.5) / levels.length <= progress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, w, h), Radius.circular(w)),
        Paint()..color = played ? TraceColors.ember : TraceColors.textFaint.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.progress != progress || old.levels != levels;
}

String clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
