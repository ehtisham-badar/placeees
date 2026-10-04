import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/api/geo.dart';
import '../../core/api/trace_api.dart';
import '../../core/api/venue.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/drop_glyph.dart';
import '../../ui/pulse_rings.dart';
import '../compass/compass_page.dart';
import '../compass/hot_cold.dart';
import '../unlock/unlock_page.dart';

/// What opens after scanning a venue QR code or tapping its NFC tag (spec F-16).
/// The drop still only opens on site.
class VenuePage extends StatefulWidget {
  const VenuePage({super.key, required this.code});

  final String code;

  @override
  State<VenuePage> createState() => _VenuePageState();
}

class _VenuePageState extends State<VenuePage> {
  Venue? _venue;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    context.read<LocationService>().start();
    context.read<TraceApi>().venue(widget.code).then(
          (v) => mounted ? setState(() => _venue = v) : null,
          onError: (Object e) => mounted ? setState(() => _error = e is ApiError ? e : const ApiError('not_found')) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final v = _venue;
    final fix = context.watch<LocationService>().fix;
    final toCenter = v == null || fix == null ? null : metersBetween(fix.point, v.drop.center);
    final inside = toCenter != null && toCenter <= v!.drop.radius;
    final huntable = toCenter != null && toCenter - v!.drop.radius <= compassMaxRange;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Column(
            children: [
              const SizedBox(height: Space.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OrbButton(icon: Icons.close_rounded, onTap: () => Navigator.pop(context), tooltip: 'Close'),
              ),
              const Spacer(),
              if (v == null)
                _error == null
                    ? const CircularProgressIndicator(color: TraceColors.ember)
                    : Column(
                        children: [
                          Text('This code has moved on.', textAlign: TextAlign.center, style: serif(size: 28)),
                          const SizedBox(height: Space.sm),
                          Text('There may be other drops nearby.', style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      )
              else ...[
                PulseRings(size: 200, child: DropGlyph(type: v.drop.type, size: 56)),
                const SizedBox(height: Space.lg),
                Text(
                  'Something is waiting at ${v.name}',
                  textAlign: TextAlign.center,
                  style: serif(size: 30, weight: FontWeight.w500, height: 1.1),
                ),
                if (v.drop.teaser != null) ...[
                  const SizedBox(height: Space.md),
                  Text(
                    '“${v.drop.teaser}”',
                    textAlign: TextAlign.center,
                    style: serif(size: 20, style: FontStyle.italic, color: TraceColors.sun),
                  ),
                ],
                const SizedBox(height: Space.md),
                Text(
                  toCenter == null
                      ? 'Finding you…'
                      : inside
                          ? 'You’re here. It opens for people standing right on the spot.'
                          : 'It’s ${distanceLabel(toCenter - v.drop.radius)} away. Head there to open it.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: TraceColors.textMuted),
                ),
              ],
              const Spacer(),
              if (v != null) ...[
                if (inside)
                  PrimaryButton(
                    label: 'Try to unlock',
                    icon: Icons.fingerprint_rounded,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      PageRouteBuilder(
                        opaque: false,
                        pageBuilder: (_, _, _) => UnlockPage(drop: v.drop),
                        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
                      ),
                    ),
                  ),
                if (huntable) ...[
                  if (inside) const SizedBox(height: Space.sm),
                  GhostButton(
                    label: 'Find the exact spot',
                    icon: Icons.explore_rounded,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => CompassPage(drop: v.drop)),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      ),
    );
  }
}
