import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class RestNotification {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _countdownId = 1002;
  static const _alertId = 1003;

  static const _countdownChannelId = 'rest_countdown';
  static const _countdownChannelName = 'Rest countdown';

  static const _alertChannelId = 'rest_finished';
  static const _alertChannelName = 'Rest finished';

  static final _buzzPattern = Int64List.fromList([0, 400, 200, 400]);

  static bool _initialised = false;

  static Future<void> init() async {
    if (_initialised) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
      _initialised = true;
    } catch (e) {
      debugPrint('RestNotification.init failed: $e');
    }
  }

  static Future<bool> ensurePermission() async {
    await init();

    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? false;
        if (granted &&
            !(await android.canScheduleExactNotifications() ?? true)) {
          await android.requestExactAlarmsPermission();
        }
        return granted;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, badge: false) ?? false;
      }
    } catch (e) {
      debugPrint('RestNotification.ensurePermission failed: $e');
    }

    return true;
  }

  static Future<void> start({
    required DateTime endsAt,
    required Duration total,
    required String exercise,
  }) async {
    await init();
    await _showCountdown(endsAt: endsAt, total: total, exercise: exercise);
    await _scheduleAlert(endsAt: endsAt, exercise: exercise);
  }

  static Future<void> _showCountdown({
    required DateTime endsAt,
    required Duration total,
    required String exercise,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _countdownChannelId,
        _countdownChannelName,
        channelDescription: 'Counts down the rest between sets.',
        ongoing: true,
        autoCancel: false,
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        showWhen: true,
        when: endsAt.millisecondsSinceEpoch,
        usesChronometer: true,
        chronometerCountDown: true,
        timeoutAfter: total.inMilliseconds,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentSound: false,
        presentBadge: false,
      ),
    );

    try {
      await _plugin.show(
        id: _countdownId,
        title: 'Resting',
        body: exercise,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('RestNotification._showCountdown failed: $e');
    }
  }

  static Future<void> _scheduleAlert({
    required DateTime endsAt,
    required String exercise,
  }) async {
    if (!endsAt.isAfter(DateTime.now())) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannelId,
        _alertChannelName,
        channelDescription: 'Buzzes when a rest period is over.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        enableVibration: true,
        vibrationPattern: _buzzPattern,
        autoCancel: true,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentBadge: false,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: _alertId,
        scheduledDate: tz.TZDateTime.from(endsAt, tz.UTC),
        androidScheduleMode: await _scheduleMode(),
        title: 'Rest over',
        body: exercise,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('RestNotification._scheduleAlert failed: $e');
    }
  }

  static Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;

    final exact = await android.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static Future<void> clear() async {
    try {
      await _plugin.cancel(id: _countdownId);
      await _plugin.cancel(id: _alertId);
    } catch (e) {
      debugPrint('RestNotification.clear failed: $e');
    }
  }

  static Future<void> clearCountdown() async {
    try {
      await _plugin.cancel(id: _countdownId);
    } catch (e) {
      debugPrint('RestNotification.clearCountdown failed: $e');
    }
  }
}
