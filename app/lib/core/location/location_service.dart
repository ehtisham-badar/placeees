import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../api/models.dart';
import '../config.dart';

enum LocationAccess { unknown, granted, denied, deniedForever, serviceDisabled }

/// Foreground location only. The app never sends a location history anywhere:
/// fixes are attached to individual requests (nearby, unlock, create) and nothing else.
class LocationService extends ChangeNotifier {
  LocationAccess access = LocationAccess.unknown;
  LocationFix? fix;

  /// Demo mode only: a manually placed position ("walk there").
  bool simulated = false;

  StreamSubscription<Position>? _sub;

  /// Fallback for demo mode when the device has no location (e.g. a fresh simulator).
  static const _demoFallback = LatLng(31.5925, 74.3095); // Lahore

  Future<void> refreshAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _setAccess(LocationAccess.serviceDisabled);
      return;
    }
    _setAccess(_map(await Geolocator.checkPermission()));
  }

  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _setAccess(LocationAccess.serviceDisabled);
      return access;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    _setAccess(_map(p));
    return access;
  }

  Future<void> start() async {
    await refreshAccess();
    if (access != LocationAccess.granted) {
      if (AppConfig.isDemo && fix == null) simulateAt(_demoFallback);
      return;
    }
    _sub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3),
    ).listen(_onPosition, onError: (_) {});

    if (AppConfig.isDemo) {
      // Simulators often have no location set; don't leave the demo staring at an empty map.
      Future.delayed(const Duration(seconds: 4), () {
        if (fix == null) simulateAt(_demoFallback);
      });
    }
  }

  /// A fix no older than [maxAge], waiting for a fresh one if needed.
  Future<LocationFix?> freshFix({Duration maxAge = const Duration(seconds: 10)}) async {
    final current = fix;
    if (simulated && current != null) return _restamp(current);
    if (current != null && DateTime.now().difference(current.timestamp) < maxAge) return current;
    if (access != LocationAccess.granted) return current;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 8)),
      );
      _onPosition(p);
    } catch (_) {}
    return fix;
  }

  void simulateAt(LatLng point) {
    simulated = true;
    fix = LocationFix(lat: point.latitude, lng: point.longitude, accuracy: 8, timestamp: DateTime.now());
    notifyListeners();
  }

  void _onPosition(Position p) {
    if (simulated) return;
    fix = LocationFix(
      lat: p.latitude,
      lng: p.longitude,
      accuracy: p.accuracy,
      speed: p.speed >= 0 ? p.speed : null,
      timestamp: p.timestamp,
      mocked: p.isMocked,
    );
    notifyListeners();
  }

  LocationFix _restamp(LocationFix f) =>
      LocationFix(lat: f.lat, lng: f.lng, accuracy: f.accuracy, timestamp: DateTime.now());

  void _setAccess(LocationAccess a) {
    if (a == access) return;
    access = a;
    notifyListeners();
  }

  static LocationAccess _map(LocationPermission p) => switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        LocationPermission.denied => LocationAccess.denied,
        LocationPermission.unableToDetermine => LocationAccess.unknown,
      };

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
