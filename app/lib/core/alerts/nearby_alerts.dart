import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:native_geofence/native_geofence.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/geo.dart';
import '../api/models.dart';

const maxGeofences = 20;
const maxAlertsPerDay = 3;

const _enabledKey = 'alerts.enabled';
const _registeredKey = 'alerts.registered';
String _teaserKey(String id) => 'alerts.teaser.$id';
String _shownKey(String id) => 'alerts.shown.$id';
String _dayKey(DateTime d) => 'alerts.day.${d.year}-${d.month}-${d.day}';

/// The drops worth watching: locked, live and nearest first (spec F-15).
@visibleForTesting
List<NearbyDrop> geofenceCandidates(List<NearbyDrop> drops, LatLng here) {
  final eligible = drops.where((d) => !d.canOpenAnywhere && !d.pending && !d.isSealed).toList()
    ..sort((a, b) => metersBetween(here, a.center).compareTo(metersBetween(here, b.center)));
  return eligible.take(maxGeofences).toList();
}

/// Whether another alert may be shown today, and for this drop. Records it if so.
@visibleForTesting
Future<bool> claimAlert(SharedPreferences prefs, String dropId, DateTime now) async {
  final day = _dayKey(now);
  final count = prefs.getInt(day) ?? 0;
  if (count >= maxAlertsPerDay) return false;
  final last = prefs.getInt(_shownKey(dropId));
  if (last != null && now.millisecondsSinceEpoch - last < const Duration(hours: 24).inMilliseconds) return false;
  await prefs.setInt(day, count + 1);
  await prefs.setInt(_shownKey(dropId), now.millisecondsSinceEpoch);
  return true;
}

final _notifications = FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() => _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

/// Runs in a background isolate when the OS reports entering a watched drop's circle.
@pragma('vm:entry-point')
Future<void> onGeofence(GeofenceCallbackParams params) async {
  if (params.event != GeofenceEvent.enter) return;
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_enabledKey) != true) return;

  for (final g in params.geofences) {
    if (!await claimAlert(prefs, g.id, DateTime.now())) continue;
    await _initNotifications();
    final teaser = prefs.getString(_teaserKey(g.id));
    await _notifications.show(
      id: g.id.hashCode & 0x7fffffff,
      title: 'Something is waiting nearby',
      body: teaser == null || teaser.isEmpty ? 'A drop is glowing within a few steps of you.' : '“$teaser”',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'nearby',
          'Nearby drops',
          channelDescription: 'A gentle nudge when you walk past a drop (at most 3 a day).',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: g.id,
    );
    return; // one nudge per event is plenty
  }
}

/// Opt-in alerts when you walk past a drop, even with the app closed (spec F-15).
class NearbyAlerts extends ChangeNotifier {
  bool enabled = false;
  bool _initialized = false;
  String _lastSet = '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_enabledKey) ?? false;
    notifyListeners();
  }

  /// Asks for notifications and "always" location, then turns alerts on. Returns whether it worked.
  Future<bool> enable() async {
    await _initNotifications();
    if (Platform.isAndroid) {
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    }
    if (!(await Permission.locationWhenInUse.request()).isGranted) return false;
    // Background location is a separate prompt (a trip to Settings on Android 11+).
    if (!(await Permission.locationAlways.request()).isGranted) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    enabled = true;
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    enabled = false;
    _lastSet = '';
    notifyListeners();
    try {
      await _manager().removeAllGeofences();
    } catch (_) {}
  }

  Future<NativeGeofenceManager> _managerReady() async {
    if (!_initialized) {
      await NativeGeofenceManager.instance.initialize();
      _initialized = true;
    }
    return NativeGeofenceManager.instance;
  }

  NativeGeofenceManager _manager() => NativeGeofenceManager.instance;

  /// Re-registers geofences for the nearest locked drops. Cheap when nothing changed.
  Future<void> sync(List<NearbyDrop> drops, LatLng here) async {
    if (!enabled) return;
    final picks = geofenceCandidates(drops, here);
    final key = picks.map((d) => d.id).join(',');
    if (key == _lastSet) return;
    _lastSet = key;

    try {
      final manager = await _managerReady();
      final prefs = await SharedPreferences.getInstance();
      await manager.removeAllGeofences();
      for (final d in picks) {
        await prefs.setString(_teaserKey(d.id), d.teaser ?? '');
        await manager.createGeofence(
          Geofence(
            id: d.id,
            location: Location(latitude: d.center.latitude, longitude: d.center.longitude),
            radiusMeters: d.radius,
            triggers: {GeofenceEvent.enter},
            iosSettings: const IosGeofenceSettings(initialTrigger: false),
            androidSettings: const AndroidGeofenceSettings(initialTriggers: {}),
          ),
          onGeofence,
        );
      }
      await prefs.setStringList(_registeredKey, [for (final d in picks) d.id]);
    } catch (_) {
      _lastSet = ''; // retry on the next refresh
    }
  }
}
