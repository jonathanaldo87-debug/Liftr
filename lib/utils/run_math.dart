import 'dart:math' as math;

/// The arithmetic behind a tracked run: turning a stream of GPS fixes into a
/// distance, and turning that distance into something readable.
///
/// Pure — no geolocator, no plugins, no clock. Everything is a function of its
/// arguments, which is what makes the parts that silently corrupt data testable
/// without a phone and a field. Deliberately does not use
/// `Geolocator.distanceBetween`: that would drag the plugin into the one layer
/// worth unit testing, and the haversine below is the same calculation.

/// One GPS reading, stripped to what the maths needs.
///
/// A plain value type rather than geolocator's `Position` so tests can build
/// fixes directly and the service stays the only thing that knows about the
/// plugin.
class GpsSample {
  final double latitude;
  final double longitude;

  /// Radius of uncertainty in metres, as reported by the OS. Bigger is worse.
  final double accuracy;

  final DateTime timestamp;

  const GpsSample({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });
}

/// Fixes worse than this are thrown away rather than trusted.
///
/// A 40 m fix in a city centre isn't a slightly worse position, it's a position
/// that can wander half a street between readings and add distance you never
/// ran.
const double kMaxAccuracyMeters = 10;

/// Segments implying a speed above this are dropped as glitches.
///
/// 12 m/s is 43 km/h — comfortably faster than any human runs and far below
/// anything a car would sustain, so this only ever catches the GPS teleporting.
/// It is not smoothing or sensor fusion; it's a guard against one bad fix
/// silently adding a kilometre to an otherwise good run.
const double kMaxPlausibleSpeedMps = 12;

/// Whether a fix is good enough to build distance from.
bool isUsableFix(GpsSample s,
        {double maxAccuracyMeters = kMaxAccuracyMeters}) =>
    s.accuracy > 0 && s.accuracy <= maxAccuracyMeters;

/// Great-circle distance between two points, in metres.
///
/// Haversine on a spherical earth. Good to well under a metre over the
/// distances between consecutive GPS fixes, which is far below the error in the
/// fixes themselves.
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

/// Accumulates distance from a stream of fixes.
///
/// Stateful but pure: feed it samples, read [totalMeters]. The first usable fix
/// is the baseline and contributes nothing — distance is only ever counted
/// between two points you actually stood at, so the walk to the start line and
/// the seconds spent waiting for a lock don't end up in the total.
///
/// Unusable fixes are skipped entirely rather than used as the next anchor.
/// Anchoring on a bad fix would launder its error into the run twice: once
/// arriving, once leaving.
class DistanceAccumulator {
  final double maxAccuracyMeters;
  final double maxSpeedMps;

  DistanceAccumulator({
    this.maxAccuracyMeters = kMaxAccuracyMeters,
    this.maxSpeedMps = kMaxPlausibleSpeedMps,
  });

  GpsSample? _last;
  double _totalMeters = 0;

  /// Metres covered so far.
  double get totalMeters => _totalMeters;

  /// Whether a baseline has been established — i.e. at least one usable fix has
  /// arrived and the run can meaningfully start.
  bool get hasBaseline => _last != null;

  /// Number of fixes rejected, for the "GPS is struggling" state.
  int get rejectedCount => _rejected;
  int _rejected = 0;

  /// Feeds one fix in. Returns the distance this fix added, which is 0 for the
  /// baseline, for a rejected fix, or for standing still.
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

    // A jump no runner could have made is the GPS lying, not you sprinting.
    // Drop the segment but keep the new fix as the anchor: the position is
    // probably right now even though the leap to it wasn't real.
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

  /// Throws away the baseline and the total. Used when a run is restarted
  /// rather than resumed.
  void reset() {
    _last = null;
    _totalMeters = 0;
    _rejected = 0;
  }

  /// Restores a total without a baseline — how a crash-recovered run picks up
  /// where it left off without inventing a segment between the last fix before
  /// the crash and the first one after it.
  void restore(double meters) {
    _totalMeters = meters;
    _last = null;
  }
}

/// Total distance from a list of fixes. The batch form of [DistanceAccumulator],
/// for tests and for replaying a recovered run.
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

// ── Formatting ────────────────────────────────────────────────

/// "840 m" under a kilometre, "5.12 km" over it.
///
/// Switches unit rather than showing "0.84 km", which reads as less precise
/// than it is, or "5120 m", which nobody says out loud.
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

/// "32:10", or "1:05:32" once it runs past an hour.
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final hours = s ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  final secs = s % 60;

  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = secs.toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// "5:30 /km", or an em dash when there isn't enough to divide by.
///
/// Pace over a few metres is a meaningless number that swings wildly, so
/// anything under 50 m reports nothing rather than something absurd.
String formatPace(double meters, int seconds) {
  if (meters < 50 || seconds <= 0) return '—';

  final secondsPerKm = seconds / (meters / 1000);
  final minutes = secondsPerKm ~/ 60;
  final secs = (secondsPerKm % 60).round();

  // 4:60 /km is not a thing.
  if (secs == 60) return '${minutes + 1}:00 /km';
  return '$minutes:${secs.toString().padLeft(2, '0')} /km';
}

/// What's left to run, never negative — overshooting a target shows 0, not -12.
double remainingMeters(double targetMeters, double actualMeters) {
  final left = targetMeters - actualMeters;
  return left < 0 ? 0 : left;
}
