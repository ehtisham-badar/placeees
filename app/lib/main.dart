import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/alerts/nearby_alerts.dart';
import 'core/analytics.dart';
import 'core/api/demo_api.dart';
import 'core/api/live_api.dart';
import 'core/api/trace_api.dart';
import 'core/auth/session.dart';
import 'core/config.dart';
import 'core/events.dart';
import 'core/location/location_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final TraceApi api = AppConfig.isDemo ? DemoApi() : LiveApi(AppConfig.apiUrl);

  runApp(
    MultiProvider(
      providers: [
        Provider<TraceApi>.value(value: api),
        Provider<Analytics>(create: (_) => Analytics(api), dispose: (_, a) => a.dispose()),
        ChangeNotifierProvider(create: (_) => Session(api)..restore()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => DataEvents()),
        ChangeNotifierProvider(create: (_) => NearbyAlerts()..load()),
      ],
      child: const TraceApp(),
    ),
  );
}
