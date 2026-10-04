import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/auth/session.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'features/map/map_page.dart';
import 'features/onboarding/handle_page.dart';
import 'features/onboarding/home_zone_page.dart';
import 'features/onboarding/location_page.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/venues/link_handler.dart';
import 'ui/pulse_rings.dart';

class TraceApp extends StatefulWidget {
  const TraceApp({super.key});

  @override
  State<TraceApp> createState() => _TraceAppState();
}

class _TraceAppState extends State<TraceApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trace',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: LinkHandler(navigator: _navigator, child: const _Root()),
    );
  }
}

/// Routes between splash, sign-in, onboarding and the map as the session changes.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final page = switch (session.stage) {
      SessionStage.loading => const _Splash(),
      SessionStage.signedOut => const WelcomePage(key: ValueKey('welcome')),
      SessionStage.onboarding => switch (session.step) {
          OnboardingStep.handle => const HandlePage(key: ValueKey('handle')),
          OnboardingStep.location => const LocationPage(key: ValueKey('location')),
          OnboardingStep.homeZone => const HomeZonePage(key: ValueKey('home')),
        },
      SessionStage.ready => const MapPage(key: ValueKey('map')),
    };

    return AnimatedSwitcher(
      duration: Motion.slow,
      switchInCurve: Motion.curve,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: page,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: PulseRings(size: 200, child: EmberDot(size: 20))));
  }
}
