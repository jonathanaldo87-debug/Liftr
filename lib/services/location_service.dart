import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../utils/run_math.dart';

/// Why a run can't start tracking yet.
///
/// Each maps to a different thing to tell the user: "turn GPS on" and "let the
/// app use your location" are fixed in different places, and lumping them into
/// one "location error" would send people to the wrong settings screen.
enum LocationAccess {
  /// Good to go — the stream can start.
  granted,

  /// Denied this once. Asking again is allowed, so the UI can offer a retry.
  denied,

  /// Denied permanently ("Don't ask again"). Only a trip to system settings
  /// fixes it, so the UI must point there rather than re-prompting into a wall.
  deniedForever,

  /// Permission is fine, but location services are switched off device-wide —
  /// nothing the app asks for will help until they're turned back on.
  serviceDisabled,
}

/// The GPS half of a tracked run: getting permission, and turning the OS
/// location stream into the plain [GpsSample]s the distance maths runs on.
///
/// Deliberately the only file that imports `geolocator`. Everything above it —
/// the accumulator, the screens — deals in [GpsSample], so the plugin can't
/// leak into the parts worth unit testing, and swapping it later touches one
/// file. Permission is handled through geolocator's own API rather than
/// `permission_handler`: two packages asking the OS the same question is how
/// their answers drift.
class LocationService {
  /// Checks location services and permission, requesting it if it hasn't been
  /// asked for yet, and reports where things stand.
  ///
  /// Services first: a granted permission is worthless with GPS switched off,
  /// and telling someone to grant access they already granted is the more
  /// confusing of the two dead ends.
  static Future<LocationAccess> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Only prompts on the first ask; a prior "deny" returns denied without
      // showing anything, which is why the result is re-read rather than assumed
      // granted.
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationAccess.granted;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
    }
  }

  /// Whether the GPS can be used right now without asking for anything —
  /// services on and permission already granted.
  ///
  /// Unlike [ensurePermission] this never prompts: it's for warming the receiver
  /// while the target's being chosen, where surfacing a permission dialog before
  /// the user has committed to a run would be out of context.
  static Future<bool> hasPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Opens the OS settings page where a permanently-denied permission can be
  /// re-granted — the only way back from [LocationAccess.deniedForever].
  static Future<void> openSettings() => Geolocator.openAppSettings();

  /// Opens the device location-services toggle, for [serviceDisabled].
  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();

  /// A stream of position fixes, tuned for someone running.
  ///
  /// The 3 m distance filter is the plan's: report a new fix every few metres
  /// rather than on a fixed clock, so standing at a light doesn't spool up
  /// readings, and the accumulator sees movement, not jitter. High accuracy asks
  /// the OS for real GPS rather than a coarse network guess — the accumulator
  /// throws away anything worse than [kMaxAccuracyMeters] anyway, so a stream of
  /// coarse fixes would just be a run that never starts.
  ///
  /// No Android foreground-service config on purpose: the run keeps the screen
  /// awake with a wakelock, so the app stays in front and the stream keeps
  /// flowing without one. The persistent notification is handled separately.
  static Stream<GpsSample> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _settings())
        .map(_toSample);
  }

  static LocationSettings _settings() {
    // Platform-specific because the two OSes expose different knobs. iOS gets
    // the activity type and auto-pause it wants for fitness tracking; Android
    // just takes accuracy and the distance filter.
    if (_isApple) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
  }

  static GpsSample _toSample(Position p) => GpsSample(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        timestamp: p.timestamp,
      );

  /// True on iOS/macOS, where [AppleSettings] is the valid settings object.
  static bool get _isApple => Platform.isIOS || Platform.isMacOS;
}
