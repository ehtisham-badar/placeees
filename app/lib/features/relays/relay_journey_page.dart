import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/signature.dart';
import '../../core/api/trace_api.dart';
import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../map/night_tiles.dart';

/// Everywhere a relay has been, as a path across the night map (spec F-13).
class RelayJourneyPage extends StatefulWidget {
  const RelayJourneyPage({super.key, required this.dropId});

  final String dropId;

  @override
  State<RelayJourneyPage> createState() => _RelayJourneyPageState();
}

class _RelayJourneyPageState extends State<RelayJourneyPage> {
  RelayJourney? _journey;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    context.read<TraceApi>().relayJourney(widget.dropId).then(
          (j) => mounted ? setState(() => _journey = j) : null,
          onError: (Object e) => mounted && e is ApiError ? setState(() => _error = e) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final j = _journey;
    if (j == null) {
      return Scaffold(
        body: Center(
          child: _error == null ? const CircularProgressIndicator(color: TraceColors.ember) : Text(_error!.message),
        ),
      );
    }

    final path = j.path;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCameraFit: path.length < 2
                  ? null
                  : CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(path),
                      padding: EdgeInsets.fromLTRB(48, 120, 48, MediaQuery.sizeOf(context).height * 0.48),
                    ),
              initialCenter: path.first,
              initialZoom: 14,
              backgroundColor: TraceColors.ink,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              const NightTiles(),
              PolylineLayer(
                polylines: [
                  // A soft glow under a crisp line.
                  Polyline(points: path, strokeWidth: 10, color: TraceColors.ember.withValues(alpha: 0.18)),
                  Polyline(
                    points: path,
                    strokeWidth: 2.4,
                    color: TraceColors.ember,
                    pattern: StrokePattern.dashed(segments: const [10, 6]),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final (i, p) in path.indexed)
                    Marker(point: p, width: 34, height: 34, child: _Stop(index: i, last: i == path.length - 1)),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: OrbButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context), tooltip: 'Back'),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.2,
            maxChildSize: 0.85,
            builder: (context, controller) => Container(
              decoration: BoxDecoration(
                color: TraceColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
                border: Border.all(color: TraceColors.line),
              ),
              child: ListView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, MediaQuery.paddingOf(context).bottom + Space.lg),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: Space.md),
                      decoration: BoxDecoration(color: TraceColors.line, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Text(distanceLabel(j.totalDistanceM), style: serif(size: 40, weight: FontWeight.w600, color: TraceColors.ember)),
                  Text(
                    'travelled, by ${j.hops.length} ${j.hops.length == 1 ? 'person' : 'people'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Space.lg),
                  _Leg(
                    index: 0,
                    title: j.originHandle == null ? 'Left by someone' : 'Left by @${j.originHandle}',
                    when: j.originAt,
                  ),
                  for (final (i, h) in j.hops.indexed)
                    _Leg(
                      index: i + 1,
                      title: '@${h.handle ?? 'someone'} carried it ${distanceLabel(h.distanceM)}',
                      when: h.droppedAt,
                      note: h.note,
                    ),
                  if (j.carriedBy != null)
                    _Leg(index: j.hops.length + 1, title: 'Now in @${j.carriedBy}’s pocket', when: null, live: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.index, required this.last});

  final int index;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = last ? TraceColors.sun : TraceColors.ember;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TraceColors.ink,
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: last ? 16 : 8)],
      ),
      child: Text('${index + 1}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.index, required this.title, required this.when, this.note, this.live = false});

  final int index;
  final String title;
  final DateTime? when;
  final String? note;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (live ? TraceColors.sun : TraceColors.ember).withValues(alpha: 0.15),
            ),
            child: live
                ? const Icon(Icons.back_hand_rounded, size: 13, color: TraceColors.sun)
                : Text('${index + 1}', style: const TextStyle(color: TraceColors.ember, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: Space.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (when != null) Text(timeAgo(when!), style: const TextStyle(color: TraceColors.textFaint, fontSize: 12)),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text('“$note”', style: serif(size: 16, style: FontStyle.italic, color: TraceColors.textMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

