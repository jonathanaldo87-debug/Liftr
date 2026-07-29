import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../utils/run_math.dart';

enum LocationAccess {
  granted,

  denied,

  deniedForever,

  serviceDisabled,
}

class LocationService {
  static Future<LocationAccess> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
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

  static Future<bool> hasPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<void> openSettings() => Geolocator.openAppSettings();

  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();

  static Stream<GpsSample> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _settings())
        .map(_toSample);
  }

  static LocationSettings _settings() {
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

  static bool get _isApple => Platform.isIOS || Platform.isMacOS;
}
