import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/drop_glyph.dart';
import '../../ui/pulse_rings.dart';

IconData conditionIcon(String? kind) => switch (kind) {
      'night' => Icons.nightlight_round,
      'sun' => Icons.wb_twilight_rounded,
      'weather' => Icons.water_drop_rounded,
      'timeRange' => Icons.schedule_rounded,
      'dateRange' => Icons.event_rounded,
      _ => Icons.auto_awesome_rounded,
    };

Color dropColor(NearbyDrop d) {
  if (d.pending) return TraceColors.textMuted;
  if (d.unlocked || d.mine) return TraceColors.mint;
  if (d.circle != null) return TraceColors.iris;
  return TraceColors.ember;
}

/// The orb at the centre of a fuzzy circle. Locked drops breathe; selected ones radiate.
class DropMarker extends StatefulWidget {
  const DropMarker({super.key, required this.drop, required this.selected});

  final NearbyDrop drop;
  final bool selected;

  @override
  State<DropMarker> createState() => _DropMarkerState();
}

class _DropMarkerState extends State<DropMarker> with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drop;
    final color = dropColor(d);
    final locked = !d.unlocked && !d.mine;
    final badge = d.isSealed
        ? Icons.hourglass_top_rounded
        : d.hasCondition && !d.canOpenAnywhere
            ? conditionIcon(d.conditionKinds.firstOrNull)
            : d.pending
                ? Icons.schedule_rounded
                : d.trail != null
                    ? Icons.route_rounded
                    : d.circle != null
                        ? Icons.group_rounded
                        : null;

    final orb = AnimatedBuilder(
      animation: _breath,
      builder: (_, child) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TraceColors.ink,
          border: Border.all(color: color, width: 1.6),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: locked ? 0.25 + 0.35 * _breath.value : 0.3),
              blurRadius: 14 + 10 * (locked ? _breath.value : 0.5),
            ),
          ],
        ),
        child: child,
      ),
      child: Icon(dropIcon(d.type), color: color, size: 19),
    );

    return AnimatedScale(
      scale: widget.selected ? 1.18 : 1,
      duration: Motion.medium,
      curve: Curves.easeOutBack,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.selected) PulseRings(size: 96, color: color, rings: 2, period: const Duration(milliseconds: 2000)),
          orb,
          if (badge != null)
            Positioned(
              right: 22,
              top: 22,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TraceColors.surfaceHigh,
                  border: Border.all(color: TraceColors.ink, width: 2),
                ),
                child: Icon(badge, size: 11, color: TraceColors.sun),
              ),
            ),
        ],
      ),
    );
  }
}

/// You: a warm white dot with a soft halo.
class UserDot extends StatelessWidget {
  const UserDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const PulseRings(size: 70, color: TraceColors.text, rings: 2, period: Duration(milliseconds: 2600)),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TraceColors.text,
            border: Border.all(color: TraceColors.ink, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x88FFFFFF), blurRadius: 12)],
          ),
        ),
      ],
    );
  }
}
