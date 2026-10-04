import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';
import 'push_service.dart';

enum PushReason { drop, capsule, relay }

/// Asks once, at a moment where a notification obviously helps, before the OS prompt.
Future<void> maybeAskForPush(BuildContext context, PushReason reason) async {
  final push = context.read<PushService>();
  if (!await push.shouldSoftAsk() || !context.mounted) return;

  final (title, body) = switch (reason) {
    PushReason.drop => ('Want to know when someone finds it?', 'We’ll nudge you when a visitor leaves an echo on your drop.'),
    PushReason.capsule => ('We’ll tell you when it opens.', 'Time capsules can wait for years. Let us remember the date for you.'),
    PushReason.relay => ('Don’t let it go home early.', 'We’ll remind you a day before your relay needs a new spot.'),
  };

  final yes = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Container(
        margin: const EdgeInsets.all(Space.sm + 4),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: TraceColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: TraceColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: PulseRings(
                size: 96,
                rings: 2,
                color: TraceColors.sun,
                child: Icon(Icons.notifications_active_rounded, color: TraceColors.sun),
              ),
            ),
            const SizedBox(height: Space.md),
            Text(title, textAlign: TextAlign.center, style: serif(size: 24, weight: FontWeight.w500)),
            const SizedBox(height: Space.sm),
            Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Space.lg),
            PrimaryButton(label: 'Turn on notifications', onPressed: () => Navigator.pop(context, true)),
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now', style: TextStyle(color: TraceColors.textMuted)),
            ),
          ],
        ),
      ),
    ),
  );
  if (yes == true) await push.enable();
}
