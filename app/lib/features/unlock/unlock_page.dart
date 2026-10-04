import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/analytics.dart';
import '../../core/api/conditions.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';
import 'drop_detail_page.dart';

enum _Phase { checking, opened, failed }

/// The unlock moment: rings converge while the server verifies you're there, then burst open.
/// Pops `true` when the drop was unlocked.
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.drop, this.onUnlocked});

  final NearbyDrop drop;

  /// Called with the drop id on success, so the map can update without a refetch.
  final ValueChanged<String>? onUnlocked;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> with TickerProviderStateMixin {
  late final _converge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  _Phase _phase = _Phase.checking;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    _attempt();
  }

  @override
  void dispose() {
    _converge.dispose();
    _burst.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _attempt() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    HapticFeedback.lightImpact();
    final started = DateTime.now();
    final api = context.read<TraceApi>();
    final fix = await context.read<LocationService>().freshFix(maxAge: const Duration(seconds: 5));

    DropContent? content;
    ApiError? error;
    try {
      if (fix == null) throw const ApiError('low_accuracy');
      content = await api.unlock(widget.drop.id, fix);
    } on ApiError catch (e) {
      error = e;
    }

    // Let the moment breathe even when the server is fast.
    final elapsed = DateTime.now().difference(started);
    const minimum = Duration(milliseconds: 1500);
    if (elapsed < minimum) await Future.delayed(minimum - elapsed);
    if (!mounted) return;

    _report(content, error);
    if (content != null) {
      setState(() => _phase = _Phase.opened);
      widget.onUnlocked?.call(widget.drop.id);
      HapticFeedback.heavyImpact();
      await _burst.forward();
      if (!mounted) return;
      final opened = content;
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: Motion.slow,
          pageBuilder: (_, _, _) => DropDetailPage(content: opened, justUnlocked: true),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
          ),
        ),
        result: true,
      );
    } else {
      setState(() {
        _phase = _Phase.failed;
        _error = error;
      });
      HapticFeedback.mediumImpact();
      _shake.forward(from: 0);
    }
  }

  void _report(DropContent? content, ApiError? error) {
    final a = context.read<Analytics>();
    a.track('unlock_attempt', {'reason': error?.code ?? 'ok'});
    if (content == null) return;
    a.track('unlock_success', {'type': content.type.wire});
    if (widget.drop.capsuleUnlockAt != null) a.track('capsule_opened');
    final trail = content.trail;
    if (trail != null && trail.seq == 1) a.track('trail_started', {'trailId': trail.id});
    if (trail != null && trail.completedAt != null && trail.isLast) a.track('trail_completed', {'trailId': trail.id});
  }

  String _failureText() {
    final rules = widget.drop.conditions;
    if (_error?.code == 'condition_locked' && rules != null && rules.isNotEmpty) {
      return 'This one only opens ${describeConditions(rules)}. Come back then.';
    }
    return _error?.message ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_phase) {
      _Phase.checking => TraceColors.ember,
      _Phase.opened => TraceColors.mint,
      _Phase.failed => TraceColors.rose,
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: TraceColors.ink.withValues(alpha: 0.86),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Close'),
                  ),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value), 0),
                      child: child,
                    ),
                    child: SizedBox.square(
                      dimension: 260,
                      child: CustomPaint(
                        painter: _ConvergePainter(_converge, _burst, color, _phase == _Phase.checking),
                        child: Center(
                          child: AnimatedContainer(
                            duration: Motion.medium,
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: TraceColors.surface,
                              border: Border.all(color: color, width: 2),
                              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 30)],
                            ),
                            child: AnimatedSwitcher(
                              duration: Motion.medium,
                              child: Icon(
                                key: ValueKey(_phase),
                                switch (_phase) {
                                  _Phase.checking => dropIcon(widget.drop.type),
                                  _Phase.opened => Icons.lock_open_rounded,
                                  _Phase.failed => Icons.lock_rounded,
                                },
                                color: color,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  AnimatedSwitcher(
                    duration: Motion.medium,
                    child: Column(
                      key: ValueKey(_phase),
                      children: [
                        Text(
                          switch (_phase) {
                            _Phase.checking => 'Checking you’re really here…',
                            _Phase.opened => 'You found it.',
                            _Phase.failed => 'Not quite.',
                          },
                          textAlign: TextAlign.center,
                          style: serif(size: 28, weight: FontWeight.w500),
                        ),
                        const SizedBox(height: Space.sm + 4),
                        Text(
                          switch (_phase) {
                            _Phase.checking => widget.drop.teaser ?? 'Hold still for a moment.',
                            _Phase.opened => 'Opening…',
                            _Phase.failed => _failureText(),
                          },
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: TraceColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: Motion.medium,
                    opacity: _phase == _Phase.failed ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: _phase != _Phase.failed,
                      child: Column(
                        children: [
                          PrimaryButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: _attempt),
                          const SizedBox(height: Space.sm),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Back to the map', style: TextStyle(color: TraceColors.textMuted)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConvergePainter extends CustomPainter {
  _ConvergePainter(this.converge, this.burst, this.color, this.active)
      : super(repaint: Listenable.merge([converge, burst]));

  final Animation<double> converge;
  final Animation<double> burst;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;

    // Rings travel inward while checking.
    if (active) {
      for (var i = 0; i < 4; i++) {
        final p = (converge.value + i / 4) % 1.0;
        final r = maxR * (1 - Curves.easeInCubic.transform(p) * 0.7);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: 0.6 * math.sin(p * math.pi)),
        );
      }
    } else {
      canvas.drawCircle(
        c,
        maxR * 0.42,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: 0.35),
      );
    }

    // Burst outward on success.
    final b = burst.value;
    if (b > 0) {
      final e = Curves.easeOutCubic.transform(b);
      canvas.drawCircle(c, maxR * 0.3 + maxR * 2.2 * e, Paint()..color = color.withValues(alpha: 0.22 * (1 - b)));
      for (var i = 0; i < 12; i++) {
        final angle = i / 12 * math.pi * 2;
        final from = c + Offset(math.cos(angle), math.sin(angle)) * (maxR * 0.35 + maxR * 0.4 * e);
        final to = c + Offset(math.cos(angle), math.sin(angle)) * (maxR * 0.45 + maxR * 0.6 * e);
        canvas.drawLine(
          from,
          to,
          Paint()
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: 1 - b),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ConvergePainter old) => old.color != color || old.active != active;
}
