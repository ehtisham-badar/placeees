import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/demo_api.dart';
import '../../core/api/geo.dart';
import '../../core/api/signature.dart';
import '../../core/api/trace_api.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';

const _minHopM = 1000.0;

/// Relays in your pocket, and where to leave them (spec F-13). Pops `true` if one was dropped.
class CarryingPage extends StatefulWidget {
  const CarryingPage({super.key});

  @override
  State<CarryingPage> createState() => _CarryingPageState();
}

class _CarryingPageState extends State<CarryingPage> {
  List<CarriedRelay>? _relays;
  bool _droppedAny = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<TraceApi>().carrying().catchError((_) => <CarriedRelay>[]);
    if (mounted) setState(() => _relays = list);
  }

  @override
  Widget build(BuildContext context) {
    final relays = _relays;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _droppedAny);
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context, _droppedAny), tooltip: 'Back'),
              ),
              const SizedBox(height: Space.lg),
              Text('In your pocket', style: serif(size: 36, weight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                'Relays travel from person to person. Leave each one somewhere you love, at least 1 km from where you found it.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.lg),
              if (relays == null)
                const Center(child: Padding(padding: EdgeInsets.all(Space.xl), child: CircularProgressIndicator()))
              else if (relays.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xl),
                  child: Column(
                    children: [
                      const PulseRings(size: 120, rings: 2, child: Icon(Icons.sync_alt_rounded, color: TraceColors.ember)),
                      const SizedBox(height: Space.md),
                      Text('Empty pockets', style: serif(size: 22)),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Open a relay on the map and pick it up to carry it on.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              else
                for (final r in relays)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: _RelayCard(
                      relay: r,
                      onDropped: () {
                        _droppedAny = true;
                        _load();
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelayCard extends StatefulWidget {
  const _RelayCard({required this.relay, required this.onDropped});

  final CarriedRelay relay;
  final VoidCallback onDropped;

  @override
  State<_RelayCard> createState() => _RelayCardState();
}

class _RelayCardState extends State<_RelayCard> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _drop() async {
    final api = context.read<TraceApi>();
    final location = context.read<LocationService>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final fix = await location.freshFix(maxAge: const Duration(seconds: 5));
      if (fix == null) throw const ApiError('low_accuracy');
      final travelled = await api.dropRelay(widget.relay.id, fix, note: _note.text);
      HapticFeedback.heavyImpact();
      messenger.showSnackBar(SnackBar(content: Text('Left it here, ${distanceLabel(travelled)} from where you found it.')));
      widget.onDropped();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.relay;
    final here = context.watch<LocationService>().fix?.point;
    final travelled = here == null ? null : metersBetween(r.pickup, here);
    final progress = ((travelled ?? 0) / _minHopM).clamp(0.0, 1.0);
    final far = (travelled ?? 0) >= _minHopM;
    final left = r.deadlineAt.difference(DateTime.now());
    final api = context.read<TraceApi>();

    return Container(
      padding: const EdgeInsets.all(Space.md + 4),
      decoration: BoxDecoration(
        color: TraceColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: far ? TraceColors.mint.withValues(alpha: 0.4) : TraceColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.teaser ?? 'A relay', style: serif(size: 20, weight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            left.inHours < 24 ? 'Goes home in ${left.inHours} h' : '${left.inDays} days left to find it a home',
            style: TextStyle(color: left.inHours < 24 ? TraceColors.rose : TraceColors.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: Motion.slow,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: TraceColors.surfaceHigh,
                color: far ? TraceColors.mint : TraceColors.ember,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            travelled == null
                ? 'Waiting for location…'
                : far
                    ? '${distanceLabel(travelled)} from where you found it. You can leave it here.'
                    : '${distanceLabel(travelled)} of 1 km. Keep going.',
            style: TextStyle(color: far ? TraceColors.mint : TraceColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (far) ...[
            const SizedBox(height: Space.md),
            TextField(
              controller: _note,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'A note for the next person (optional)', counterText: ''),
            ),
            const SizedBox(height: Space.sm + 4),
            PrimaryButton(label: 'Leave it here', icon: Icons.place_rounded, loading: _busy, onPressed: _drop),
          ],
          if (api is DemoApi && !far)
            TextButton.icon(
              onPressed: () => context.read<LocationService>().simulateAt(offsetBy(r.pickup, 45, 1200)),
              icon: const Icon(Icons.directions_bus_rounded, size: 18, color: TraceColors.textMuted),
              label: const Text('Demo: travel 1.2 km', style: TextStyle(color: TraceColors.textMuted)),
            ),
        ],
      ),
    );
  }
}
