import 'dart:async';

import 'package:flutter/foundation.dart';

import 'prefs.dart';
import 'rest_notification.dart';

class RestTimer {
  static final ValueNotifier<Duration?> remaining = ValueNotifier(null);

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static DateTime? _endsAt;
  static Duration _total = Duration.zero;
  static String _label = '';
  static Timer? _ticker;

  static bool _askedPermission = false;

  static Duration get total => _total;

  static String get label => _label;

  static bool get isRunning => _endsAt != null;

  static Future<void> start(String exercise, {Duration? duration}) async {
    final rest = duration ?? Duration(seconds: Prefs.restSeconds);
    if (rest <= Duration.zero) return;

    if (!_askedPermission) {
      _askedPermission = true;
      await RestNotification.ensurePermission();
    }

    _begin(exercise, rest);
  }

  static Future<void> addTime(Duration extra) async {
    final endsAt = _endsAt;
    if (endsAt == null) return;

    final left = endsAt.difference(clock()) + extra;
    if (left <= Duration.zero) {
      await skip();
      return;
    }

    _begin(_label, left, total: _total + extra);
  }

  static Future<void> skip() async {
    _stop();
    await RestNotification.clear();
  }

  static void _begin(String exercise, Duration rest, {Duration? total}) {
    final endsAt = clock().add(rest);

    _endsAt = endsAt;
    _total = total ?? rest;
    _label = exercise;
    remaining.value = rest;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    unawaited(RestNotification.start(
      endsAt: endsAt,
      total: rest,
      exercise: exercise,
    ));
  }

  static void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null) return;

    final left = endsAt.difference(clock());
    if (left <= Duration.zero) {
      _stop();
      unawaited(RestNotification.clearCountdown());
      return;
    }

    remaining.value = left;
  }

  static void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _total = Duration.zero;
    _label = '';
    remaining.value = null;
  }
}
