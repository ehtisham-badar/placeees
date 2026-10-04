import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// One local-notifications instance for the app: nearby alerts and foreground pushes.
final localNotifications = FlutterLocalNotificationsPlugin();

/// Set by [PushService] in the main isolate: opens the drop a tapped notification is about.
void Function(String dropId)? onNotificationTap;

const pushChannel = AndroidNotificationDetails(
  'activity',
  'Activity',
  channelDescription: 'Time capsules opening, echoes on your drops, relay reminders.',
  importance: Importance.high,
);

Future<void> initLocalNotifications() => localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) onNotificationTap?.call(id);
      },
    );
