import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class RunNotification {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _id = 1001;

  static const _channelId = 'run_session';
  static const _channelName = 'Running sessions';

  static bool _initialised = false;

  static Future<void> init() async {
    if (_initialised) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _initialised = true;
  }

  static Future<bool> ensurePermission() async {
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: false) ?? false;
    }

    return true;
  }

  static Future<void> update({
    required String title,
    required String body,
  }) async {
    await init();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Shown while a run is being tracked.',
        ongoing: true,
        autoCancel: false,
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iOS: DarwinNotificationDetails(
        presentSound: false,
        presentBadge: false,
      ),
    );

    try {
      await _plugin.show(
        id: _id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('RunNotification.update failed: $e');
    }
  }

  static Future<void> clear() async {
    try {
      await _plugin.cancel(id: _id);
    } catch (e) {
      debugPrint('RunNotification.clear failed: $e');
    }
  }
}
