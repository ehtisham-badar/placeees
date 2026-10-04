import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/analytics.dart';
import '../../core/api/api_error.dart';
import '../../core/api/signature.dart';
import '../../core/api/trace_api.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../core/push/soft_ask.dart';
import 'relay_journey_page.dart';

/// On an opened relay drop: how far it's travelled, and the chance to carry it on (spec F-13).
class RelayPanel extends StatefulWidget {
  const RelayPanel({super.key, required this.dropId, required this.relay, required this.onPickedUp});

  final String dropId;
  final RelayInfo relay;
  final VoidCallback onPickedUp;

  @override
  State<RelayPanel> createState() => _RelayPanelState();
}

class _RelayPanelState extends State<RelayPanel> {
  bool _busy = false;

  Future<void> _pickUp() async {
    final api = context.read<TraceApi>();
    final location = context.read<LocationService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final fix = await location.freshFix(maxAge: const Duration(seconds: 5));
      if (fix == null) throw const ApiError('low_accuracy');
      final deadline = await api.pickUpRelay(widget.dropId, fix);
      if (mounted) context.read<Analytics>().track('relay_picked');
      HapticFeedback.heavyImpact();
      messenger.showSnackBar(SnackBar(
        content: Text('It’s in your pocket. Leave it at least 1 km away by ${DateFormat.MMMd().format(deadline)}.'),
      ));
      if (mounted) await maybeAskForPush(context, PushReason.relay);
      widget.onPickedUp();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.code == 'too_far' ? 'Pick it up while you’re standing here.' : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.relay;
    return Container(
      padding: const EdgeInsets.all(Space.md + 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TraceColors.ember.withValues(alpha: 0.14), TraceColors.surface],
        ),
        border: Border.all(color: TraceColors.ember.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_alt_rounded, color: TraceColors.ember, size: 18),
              const SizedBox(width: 8),
              Text(
                r.hops == 0 ? 'A relay, waiting for its first carrier' : 'A relay · carried ${r.hops} ${r.hops == 1 ? 'time' : 'times'}',
                style: const TextStyle(color: TraceColors.ember, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: Space.sm + 4),
          Text(
            r.carrying
                ? 'It’s with you. Find it a new home at least 1 km from where you picked it up'
                    '${r.carryDeadline == null ? '' : ', by ${DateFormat.MMMd().format(r.carryDeadline!)}'}.'
                : r.canPickUp
                    ? 'Carry it somewhere new, at least 1 km away, within 7 days. Then leave it for the next person.'
                    : 'This drop travels from person to person, one place at a time.',
            style: serif(size: 18, height: 1.35),
          ),
          const SizedBox(height: Space.md),
          if (r.canPickUp) ...[
            PrimaryButton(label: 'Pick it up', icon: Icons.back_hand_rounded, loading: _busy, onPressed: _pickUp),
            const SizedBox(height: Space.sm),
          ],
          GhostButton(
            label: 'See where it’s been',
            icon: Icons.timeline_rounded,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RelayJourneyPage(dropId: widget.dropId)),
            ),
          ),
        ],
      ),
    );
  }
}
