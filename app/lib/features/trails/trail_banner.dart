import 'package:flutter/material.dart';

import '../../core/api/social.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import 'stamp.dart';
import 'trail_page.dart';

/// Shown on a drop that's part of a trail: where you are, and the next clue once earned.
class TrailBanner extends StatelessWidget {
  const TrailBanner({super.key, required this.trail, required this.unlocked});

  final TrailRef trail;

  /// Whether the viewer has unlocked this stop (or made it).
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final t = trail;
    final complete = t.completedAt != null;

    return Container(
      padding: const EdgeInsets.all(Space.md + 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TraceColors.sun.withValues(alpha: 0.12), TraceColors.surface],
        ),
        border: Border.all(color: TraceColors.sun.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: TraceColors.sun, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stop ${t.seq} of ${t.total} · ${t.title}',
                  style: const TextStyle(color: TraceColors.sun, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          if (complete) ...[
            Row(
              children: [
                TrailStamp(title: t.title, date: t.completedAt!, size: 92),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trail complete.', style: serif(size: 22, weight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      const Text('The stamp is in your passport.', style: TextStyle(color: TraceColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ] else if (unlocked && t.nextClue != null) ...[
            const Text('NEXT CLUE', style: TextStyle(color: TraceColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Text('“${t.nextClue}”', style: serif(size: 20, style: FontStyle.italic, height: 1.35)),
          ] else if (unlocked && t.isLast) ...[
            Text('The last stop.', style: serif(size: 20)),
          ] else
            Text('Find this stop to reveal the next clue.', style: serif(size: 18, color: TraceColors.textMuted)),
          const SizedBox(height: Space.md),
          GhostButton(
            label: 'View trail',
            icon: Icons.timeline_rounded,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrailPage(trailId: t.id))),
          ),
        ],
      ),
    );
  }
}
