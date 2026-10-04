import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/demo_api.dart';
import '../../core/api/geo.dart';
import '../../core/api/models.dart';
import '../../core/api/trace_api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';
import '../../ui/glass.dart';
import 'drop_marker.dart';

/// Bottom card for the selected drop: what it is, how far, and what you can do about it.
class DropCard extends StatelessWidget {
  const DropCard({super.key, required this.drop, required this.onClose, required this.onUnlock, required this.onOpen});

  final NearbyDrop drop;
  final VoidCallback onClose;
  final VoidCallback onUnlock;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationService>();
    final fix = location.fix;
    final toCenter = fix == null ? null : metersBetween(fix.point, drop.center);
    final inside = toCenter != null && toCenter <= drop.radius;
    final color = dropColor(drop);
    final theme = Theme.of(context);

    return Glass(
      padding: const EdgeInsets.fromLTRB(Space.md + 4, Space.md + 4, Space.md + 4, Space.md + 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DropGlyph(type: drop.type, color: color),
              const SizedBox(width: Space.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drop.mine ? 'Your ${dropNoun(drop.type).toLowerCase()}' : '${dropNoun(drop.type)} left here',
                      style: theme.textTheme.labelLarge?.copyWith(color: color),
                    ),
                    Text(timeAgo(drop.createdAt), style: theme.textTheme.bodySmall?.copyWith(color: TraceColors.textMuted)),
                  ],
                ),
              ),
              OrbButton(icon: Icons.close_rounded, size: 36, onTap: onClose, tooltip: 'Close'),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            drop.teaser ?? 'No hint. Just a feeling.',
            style: serif(size: 24, weight: FontWeight.w500, style: drop.teaser == null ? FontStyle.italic : null),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (drop.pending) const TagChip(label: 'In review', icon: Icons.schedule_rounded, color: TraceColors.amber),
              if (drop.unlocked) const TagChip(label: 'In your passport', icon: Icons.verified_rounded, color: TraceColors.mint),
              if (drop.capsuleUnlockAt != null)
                TagChip(label: countdown(drop.capsuleUnlockAt!), icon: Icons.hourglass_top_rounded, color: TraceColors.sun),
              if (drop.hasCondition)
                const TagChip(label: 'Waits for the right moment', icon: Icons.nightlight_round, color: TraceColors.sun),
              if (toCenter != null && !drop.canOpenAnywhere)
                TagChip(
                  label: inside ? "You're in the glow" : '${distanceLabel(toCenter - drop.radius)} to the glow',
                  icon: inside ? Icons.auto_awesome_rounded : Icons.directions_walk_rounded,
                  color: inside ? TraceColors.mint : TraceColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: Space.md + 4),
          _action(context, inside, toCenter),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, bool inside, double? toCenter) {
    if (drop.canOpenAnywhere) {
      return PrimaryButton(
        label: drop.pending ? 'Preview' : 'Open',
        icon: Icons.lock_open_rounded,
        gradient: const LinearGradient(colors: [TraceColors.mint, Color(0xFF9BF0DC)]),
        onPressed: onOpen,
      );
    }
    if (inside) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "It's somewhere inside this circle. Unlocking works within about 50 m of the real spot.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TraceColors.textMuted),
          ),
          const SizedBox(height: Space.sm + 4),
          PrimaryButton(label: 'Try to unlock', icon: Icons.fingerprint_rounded, onPressed: onUnlock),
          ..._demoWalk(context),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: toCenter == null ? 'Waiting for location' : 'Get closer to unlock',
          icon: Icons.lock_rounded,
        ),
        ..._demoWalk(context),
      ],
    );
  }

  List<Widget> _demoWalk(BuildContext context) {
    final api = context.read<TraceApi>();
    if (!AppConfig.isDemo || api is! DemoApi) return const [];
    return [
      const SizedBox(height: Space.sm),
      TextButton.icon(
        onPressed: () {
          final p = api.truePointOf(drop.id);
          if (p != null) context.read<LocationService>().simulateAt(offsetBy(p, 90, 12));
        },
        icon: const Icon(Icons.hiking_rounded, size: 18, color: TraceColors.textMuted),
        label: const Text('Demo: walk there', style: TextStyle(color: TraceColors.textMuted)),
      ),
    ];
  }
}
