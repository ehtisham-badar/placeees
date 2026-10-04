import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/trace_api.dart';
import '../config.dart';
import 'notifications.dart';

/// Push for capsules opening, echoes on your drops and relay deadlines.
/// iOS registers straight with APNs (the API sends there); Android uses FCM.
class PushService extends ChangeNotifier {
  PushService(this._api, {required this.openDrop});

  final TraceApi _api;

  /// Opens a drop when a notification about it is tapped.
  final void Function(String dropId) openDrop;

  static const _ios = MethodChannel('app.trace/push');
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'trace.pushToken';
  static const _askedKey = 'push.softAsked';

  bool enabled = false;
  bool _wired = false;
  StreamSubscription<String>? _refresh;
  final _subs = <StreamSubscription<RemoteMessage>>[];

  /// Push works when there's a backend, and on Android a Firebase config.
  bool get available => !AppConfig.isDemo && (Platform.isIOS || (Platform.isAndroid && AppConfig.firebaseConfigured));

  /// After each sign-in: wire up taps (once), and register this device for the account if
  /// permission was already given.
  Future<void> start() async {
    if (!available) return;
    await _wire();
    if (await _permissionGranted()) await _register();
  }

  Future<void> _wire() async {
    if (_wired) return;
    _wired = true;
    onNotificationTap = openDrop;
    await initLocalNotifications();

    if (Platform.isIOS) {
      _ios.setMethodCallHandler(_onIosCall);
      await _ios.invokeMethod('ready');
    } else {
      await localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'activity',
              'Activity',
              description: 'Time capsules opening, echoes on your drops, relay reminders.',
              importance: Importance.high,
            ),
          );
      await _initFirebase();
      final opened = await FirebaseMessaging.instance.getInitialMessage();
      if (opened != null) _openFrom(opened.data);
      _subs
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => _openFrom(m.data)))
        ..add(FirebaseMessaging.onMessage.listen(_showForeground));
    }
  }

  /// Asks for permission (if needed) and registers. Returns whether push is on.
  Future<bool> enable() async {
    if (!available) return false;
    await _wire();
    if (!await _requestPermission()) return false;
    await _register();
    return enabled;
  }

  /// On sign-out: this device stops receiving pushes for the account.
  Future<void> stop() async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      try {
        await _api.unregisterDevice(token);
      } catch (_) {}
      await _storage.delete(key: _tokenKey);
    }
    enabled = false;
    notifyListeners();
  }

  /// One gentle, in-context ask per install (after the first drop, capsule or relay).
  Future<bool> shouldSoftAsk() async {
    if (!available || enabled) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true) return false;
    await prefs.setBool(_askedKey, true);
    return !await _permissionGranted();
  }

  Future<void> _initFirebase() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAndroidAppId,
        messagingSenderId: AppConfig.firebaseSenderId,
        projectId: AppConfig.firebaseProjectId,
      ),
    );
  }

  Future<bool> _permissionGranted() async {
    if (Platform.isIOS) {
      final ios = localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    final android = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<bool> _requestPermission() async {
    if (Platform.isIOS) {
      final ios = localNotifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    final android = localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<void> _register() async {
    if (Platform.isIOS) {
      await _ios.invokeMethod('register'); // token arrives via onToken
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(token, 'android');
    _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) => _saveToken(t, 'android'));
  }

  Future<void> _saveToken(String token, String platform) async {
    try {
      await _api.registerDevice(token, platform);
      await _storage.write(key: _tokenKey, value: token);
      enabled = true;
      notifyListeners();
    } catch (_) {
      // Offline or signed out; we'll register again on the next start.
    }
  }

  Future<void> _onIosCall(MethodCall call) async {
    switch (call.method) {
      case 'onToken':
        await _saveToken(call.arguments as String, 'ios');
      case 'onTap':
        _openFrom((call.arguments as Map).cast<String, Object?>());
    }
  }

  void _openFrom(Map<String, Object?> data) {
    final id = data['dropId'];
    if (id is String && id.isNotEmpty) openDrop(id);
  }

  /// Android doesn't show FCM notifications while the app is open; show them ourselves.
  Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    await localNotifications.show(
      id: m.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(android: pushChannel),
      payload: m.data['dropId'] as String?,
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
