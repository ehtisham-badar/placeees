import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import '../../core/config.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';
import 'onboarding_scaffold.dart';

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  bool _asking = false;

  Future<void> _enable() async {
    final location = context.read<LocationService>();
    final session = context.read<Session>();
    if (location.access == LocationAccess.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }
    if (location.access == LocationAccess.serviceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    setState(() => _asking = true);
    final access = await location.requestAccess();
    if (!mounted) return;
    setState(() => _asking = false);
    if (access == LocationAccess.granted) {
      await location.start();
      session.advance(OnboardingStep.homeZone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<LocationService>().access;
    final label = switch (access) {
      LocationAccess.deniedForever => 'Open Settings',
      LocationAccess.serviceDisabled => 'Turn on Location Services',
      _ => 'Enable location',
    };

    return OnboardingScaffold(
      step: 1,
      total: 3,
      hero: const PulseRings(
        size: 150,
        color: TraceColors.sun,
        child: Icon(Icons.near_me_rounded, color: TraceColors.sun, size: 30),
      ),
      title: 'Trace works\nwhere you are.',
      body: 'Location is how drops are found and opened. Here is our promise:',
      content: const Column(
        children: [
          PromiseRow(
            icon: Icons.visibility_off_rounded,
            title: 'Never shared',
            text: 'Your live location is never shown to anyone, not even friends.',
          ),
          PromiseRow(
            icon: Icons.blur_on_rounded,
            title: 'Always blurred',
            text: 'Drops appear as soft circles, never exact pins.',
          ),
          PromiseRow(
            icon: Icons.directions_walk_rounded,
            title: 'Only in person',
            text: 'Content opens only when you are physically there.',
          ),
        ],
      ),
      actions: [
        if (access == LocationAccess.denied || access == LocationAccess.deniedForever)
          const Padding(
            padding: EdgeInsets.only(bottom: Space.sm + 4),
            child: Text(
              'Trace needs location to show and open drops.',
              style: TextStyle(color: TraceColors.amber, fontWeight: FontWeight.w600),
            ),
          ),
        PrimaryButton(label: label, icon: Icons.location_on_rounded, loading: _asking, onPressed: _enable),
        if (AppConfig.isDemo) ...[
          const SizedBox(height: Space.sm),
          TextButton(
            onPressed: () {
              context.read<LocationService>().start();
              context.read<Session>().advance(OnboardingStep.homeZone);
            },
            child: const Text('Use a simulated location', style: TextStyle(color: TraceColors.textMuted)),
          ),
        ],
      ],
    );
  }
}
