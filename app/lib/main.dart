import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/alerts/nearby_alerts.dart';
import 'core/analytics.dart';
import 'core/push/push_service.dart';
import 'features/unlock/drop_detail_page.dart';
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
  final session = Session(api);
  final push = PushService(
    api,
    openDrop: (id) => rootNavigator.currentState?.push(MaterialPageRoute(builder: (_) => DropDetailPage.load(dropId: id))),
  );
  // Each time someone signs in, register this device for their pushes.
  var wasReady = false;
  session.addListener(() {
    final ready = session.stage == SessionStage.ready;
    if (ready && !wasReady) push.start();
    wasReady = ready;
  });
  session.restore();

  runApp(
    MultiProvider(
      providers: [
        Provider<TraceApi>.value(value: api),
        Provider<Analytics>(create: (_) => Analytics(api), dispose: (_, a) => a.dispose()),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => DataEvents()),
        ChangeNotifierProvider(create: (_) => NearbyAlerts()..load()),
        ChangeNotifierProvider.value(value: push),
      ],
      child: const TraceApp(),
    ),
  );
}
