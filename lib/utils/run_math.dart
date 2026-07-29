import 'dart:math' as math;

class GpsSample {
  final double latitude;
  final double longitude;

  final double accuracy;

  final DateTime timestamp;

  const GpsSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });
}

const double kMaxAccuracyMeters = 10;

const double kMaxPlausibleSpeedMps = 12;

bool isUsableFix(GpsSample s,
        {double maxAccuracyMeters = kMaxAccuracyMeters}) =>
    s.accuracy > 0 && s.accuracy <= maxAccuracyMeters;

double haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusMeters = 6371000.0;

  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final rLat1 = _toRadians(lat1);
  final rLat2 = _toRadians(lat2);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rLat1) *
          math.cos(rLat2) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRadians(double degrees) => degrees * math.pi / 180;

class DistanceAccumulator {
  final double maxAccuracyMeters;
  final double maxSpeedMps;

  DistanceAccumulator({
    this.maxAccuracyMeters = kMaxAccuracyMeters,
    this.maxSpeedMps = kMaxPlausibleSpeedMps,
  });

  GpsSample? _last;
  double _totalMeters = 0;

  double get totalMeters => _totalMeters;

  bool get hasBaseline => _last != null;

  int get rejectedCount => _rejected;
  int _rejected = 0;

  double add(GpsSample sample) {
    if (!isUsableFix(sample, maxAccuracyMeters: maxAccuracyMeters)) {
      _rejected++;
      return 0;
    }

    final previous = _last;
    if (previous == null) {
      _last = sample;
      return 0;
    }

    final metres = haversineMeters(
      previous.latitude,
      previous.longitude,
      sample.latitude,
      sample.longitude,
    );

    final seconds =
        sample.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (seconds > 0 && metres / seconds > maxSpeedMps) {
      _last = sample;
      _rejected++;
      return 0;
    }

    _last = sample;
    _totalMeters += metres;
    return metres;
  }

  void reset() {
    _last = null;
    _totalMeters = 0;
    _rejected = 0;
  }

  void restore(double meters) {
    _totalMeters = meters;
    _last = null;
  }
}

double accumulateDistance(
  Iterable<GpsSample> samples, {
  double maxAccuracyMeters = kMaxAccuracyMeters,
  double maxSpeedMps = kMaxPlausibleSpeedMps,
}) {
  final acc = DistanceAccumulator(
    maxAccuracyMeters: maxAccuracyMeters,
    maxSpeedMps: maxSpeedMps,
  );
  for (final s in samples) {
    acc.add(s);
  }
  return acc.totalMeters;
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final hours = s ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  final secs = s % 60;

  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = secs.toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatPace(double meters, int seconds) {
  if (meters < 50 || seconds <= 0) return '—';

  final secondsPerKm = seconds / (meters / 1000);
  final minutes = secondsPerKm ~/ 60;
  final secs = (secondsPerKm % 60).round();

  if (secs == 60) return '${minutes + 1}:00 /km';
  return '$minutes:${secs.toString().padLeft(2, '0')} /km';
}

double remainingMeters(double targetMeters, double actualMeters) {
  final left = targetMeters - actualMeters;
  return left < 0 ? 0 : left;
}
