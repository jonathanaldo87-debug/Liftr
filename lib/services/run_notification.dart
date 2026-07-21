import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The persistent "run in progress" notification.
///
/// One ongoing notification for the length of a tracked run — the badge that
/// says the app is doing something even when you've swiped away to change a
/// song, and the fastest way back into the run. It updates in place with the
/// distance remaining rather than stacking a new notification each time, and is
/// cancelled the instant the session ends.
///
/// Wraps `flutter_local_notifications` so the plugin lives in one file, the same
/// way [LocationService] fences off geolocator.
class RunNotification {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// A fixed id: there is only ever one run notification, and reusing the id is
  /// what makes [update] replace the existing one instead of piling up a new
  /// row for every distance change.
  static const _id = 1001;

  static const _channelId = 'run_session';
  static const _channelName = 'Running sessions';

  static bool _initialised = false;

  /// Wires up the plugin and asks for notification permission on the platforms
  /// that gate it (Android 13+, iOS). Safe to call more than once — the actual
  /// setup runs only the first time.
  static Future<void> init() async {
    if (_initialised) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      // The run screen requests location right after this; not stacking a
      // notification prompt on top of it keeps the first-run flow to one ask at
      // a time. Permission is requested lazily in [ensurePermission] instead.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _initialised = true;
  }

  /// Asks for permission to post notifications, returning whether it's granted.
  ///
  /// Split out from [init] so it can be requested at the moment a run starts —
  /// where the user has just chosen to track something and the ask has obvious
  /// context — rather than on a cold launch where it reads as noise.
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

  /// Shows or updates the ongoing notification with [title]/[body].
  ///
  /// Failures are swallowed: a run that can't post a notification is a run
  /// missing a nicety, not one that should fall over. The distance still tracks.
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
        // ongoing + autoCancel:false is what makes it un-swipeable for the
        // duration; the run owns it and only the run dismisses it.
        ongoing: true,
        autoCancel: false,
        // A tracking badge, not an interruption: no sound, no vibration, and
        // low importance so it sits quietly in the shade.
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

  /// Clears the notification. Called when the session ends, by any route —
  /// saved, discarded, or the last interval finished.
  static Future<void> clear() async {
    try {
      await _plugin.cancel(id: _id);
    } catch (e) {
      debugPrint('RunNotification.clear failed: $e');
    }
  }
}
