import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/session.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/pulse_rings.dart';
import 'onboarding_scaffold.dart';

class HomeZonePage extends StatefulWidget {
  const HomeZonePage({super.key});

  @override
  State<HomeZonePage> createState() => _HomeZonePageState();
}

class _HomeZonePageState extends State<HomeZonePage> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Already set for this account (e.g. signing back in): nothing to ask.
    final session = context.read<Session>();
    if (session.user?.hasHomeZone ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => session.finishOnboarding());
    }
  }

  Future<void> _setHere() async {
    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final fix = await context.read<LocationService>().freshFix();
      if (fix == null) {
        messenger.showSnackBar(const SnackBar(content: Text("We couldn't get a location fix. Try again outside.")));
        return;
      }
      session.updateUser(await session.api.setHomeZone(fix.lat, fix.lng));
      messenger.showSnackBar(const SnackBar(content: Text('Home is now a quiet zone.')));
      await session.finishOnboarding();
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: 2,
      total: 3,
      hero: const PulseRings(
        size: 150,
        color: TraceColors.mint,
        child: Icon(Icons.home_rounded, color: TraceColors.mint, size: 30),
      ),
      title: 'Make home\na quiet zone.',
      body: 'No public drops can be left within 200 m of your home, so nothing you post can lead '
          'back to your door. We store it slightly blurred, and never show it to anyone.',
      actions: [
        PrimaryButton(label: "I'm home, set it", icon: Icons.shield_moon_rounded, loading: _saving, onPressed: _setHere),
        const SizedBox(height: Space.sm),
        TextButton(
          onPressed: _saving ? null : () => context.read<Session>().finishOnboarding(),
          child: const Text('Skip for now', style: TextStyle(color: TraceColors.textMuted)),
        ),
      ],
    );
  }
}
