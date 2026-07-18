import 'package:flutter_test/flutter_test.dart';
import 'package:liftr/utils/run_math.dart';

/// A fix at a given offset in seconds from a fixed epoch, so tests read as a
/// sequence of moments rather than a pile of DateTimes.
GpsSample fix(
  double lat,
  double lon, {
  double accuracy = 5,
  int atSecond = 0,
}) =>
    GpsSample(
      latitude: lat,
      longitude: lon,
      accuracy: accuracy,
      timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: atSecond)),
    );

void main() {
  group('haversineMeters', () {
    test('one degree of latitude is about 111 km', () {
      final d = haversineMeters(0, 0, 1, 0);
      expect(d, closeTo(111195, 50));
    });

    test('a small step is accurate to the metre', () {
      // 0.0001° of latitude ≈ 11.1 m — the scale of consecutive GPS fixes.
      final d = haversineMeters(51.5, -0.12, 51.5001, -0.12);
      expect(d, closeTo(11.1, 0.2));
    });

    test('is zero for the same point, and symmetric', () {
      expect(haversineMeters(51.5, -0.12, 51.5, -0.12), 0);
      expect(
        haversineMeters(51.5, -0.12, 51.51, -0.13),
        closeTo(haversineMeters(51.51, -0.13, 51.5, -0.12), 0.001),
      );
    });

    test('handles the antimeridian without going the long way round', () {
      // Two points either side of the date line are close, not 40,000 km apart.
      final d = haversineMeters(0, 179.999, 0, -179.999);
      expect(d, lessThan(500));
    });
  });

  group('DistanceAccumulator', () {
    test('the first fix is a baseline and adds nothing', () {
      final acc = DistanceAccumulator();
      expect(acc.add(fix(51.5, -0.12)), 0);
      expect(acc.totalMeters, 0);
      expect(acc.hasBaseline, isTrue);
    });

    test('accumulates across a straight line of fixes', () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5000, -0.12, atSecond: 0));
      acc.add(fix(51.5001, -0.12, atSecond: 5));
      acc.add(fix(51.5002, -0.12, atSecond: 10));

      // Two 11.1 m steps.
      expect(acc.totalMeters, closeTo(22.2, 0.5));
    });

    test('standing still adds nothing', () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5, -0.12, atSecond: 0));
      acc.add(fix(51.5, -0.12, atSecond: 5));
      acc.add(fix(51.5, -0.12, atSecond: 10));
      expect(acc.totalMeters, 0);
    });

    test('drops fixes too vague to trust', () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5000, -0.12, atSecond: 0));
      acc.add(fix(51.5050, -0.12, accuracy: 40, atSecond: 5)); // junk
      acc.add(fix(51.5001, -0.12, atSecond: 10));

      // The junk fix is skipped entirely rather than becoming the next anchor,
      // so the total is the real 11.1 m — not the ~550 m out and back its error
      // would have invented.
      expect(acc.totalMeters, closeTo(11.1, 0.5));
      expect(acc.rejectedCount, 1);
    });

    test('a bad fix never becomes the anchor, so its error is not counted twice',
        () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5000, -0.12, atSecond: 0));
      acc.add(fix(51.6000, -0.12, accuracy: 50, atSecond: 5));
      acc.add(fix(51.5001, -0.12, atSecond: 10));
      expect(acc.totalMeters, closeTo(11.1, 0.5));
    });

    test('drops a teleport no runner could have made', () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5000, -0.12, atSecond: 0));
      // 1.1 km in 2 seconds, with a perfectly good accuracy reading.
      acc.add(fix(51.5100, -0.12, atSecond: 2));
      expect(acc.totalMeters, 0);
      expect(acc.rejectedCount, 1);
    });

    test('keeps a long gap that is merely a lost signal, not a teleport', () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5000, -0.12, atSecond: 0));
      // Same 1.1 km, but over four minutes — a plausible run through a tunnel.
      acc.add(fix(51.5100, -0.12, atSecond: 240));
      expect(acc.totalMeters, closeTo(1112, 20));
    });

    test('reset clears the run; restore resumes a total without a baseline', () {
      final acc = DistanceAccumulator();
      acc.add(fix(51.5000, -0.12, atSecond: 0));
      acc.add(fix(51.5001, -0.12, atSecond: 5));
      expect(acc.totalMeters, greaterThan(0));

      acc.reset();
      expect(acc.totalMeters, 0);
      expect(acc.hasBaseline, isFalse);

      // Recovering a crashed run: the total comes back, but the next fix is a
      // fresh baseline — otherwise the distance covered while the app was dead
      // would be invented as one straight segment.
      acc.restore(1500);
      expect(acc.totalMeters, 1500);
      expect(acc.hasBaseline, isFalse);
      expect(acc.add(fix(51.6, -0.12, atSecond: 300)), 0);
      expect(acc.totalMeters, 1500);
    });
  });

  group('accumulateDistance', () {
    test('is empty for no fixes and for one fix', () {
      expect(accumulateDistance([]), 0);
      expect(accumulateDistance([fix(51.5, -0.12)]), 0);
    });

    test('ignores a run made entirely of junk', () {
      final junk = [
        fix(51.5000, -0.12, accuracy: 30, atSecond: 0),
        fix(51.5010, -0.12, accuracy: 45, atSecond: 5),
        fix(51.5020, -0.12, accuracy: 60, atSecond: 10),
      ];
      expect(accumulateDistance(junk), 0);
    });
  });

  group('formatDistance', () {
    test('metres below a kilometre, kilometres above', () {
      expect(formatDistance(0), '0 m');
      expect(formatDistance(840), '840 m');
      expect(formatDistance(999), '999 m');
      expect(formatDistance(1000), '1.00 km');
      expect(formatDistance(5123.4), '5.12 km');
    });
  });

  group('formatDuration', () {
    test('minutes and seconds under an hour', () {
      expect(formatDuration(0), '0:00');
      expect(formatDuration(9), '0:09');
      expect(formatDuration(70), '1:10');
      expect(formatDuration(1930), '32:10');
    });

    test('grows an hours field rather than showing 65:32', () {
      expect(formatDuration(3932), '1:05:32');
      expect(formatDuration(3600), '1:00:00');
    });

    test('never renders negative time', () {
      expect(formatDuration(-5), '0:00');
    });
  });

  group('formatPace', () {
    test('is minutes per kilometre', () {
      // 1 km in 5:30.
      expect(formatPace(1000, 330), '5:30 /km');
      // 5 km in 27:30 — same pace.
      expect(formatPace(5000, 1650), '5:30 /km');
    });

    test('says nothing rather than something absurd over a few metres', () {
      expect(formatPace(10, 3), '—');
      expect(formatPace(0, 0), '—');
      expect(formatPace(1000, 0), '—');
    });

    test('rounds up to the next minute instead of printing :60', () {
      // 4:59.7 /km must not render as "4:60 /km".
      expect(formatPace(1000, 300 - 0.3.round()), isNot(contains(':60')));
      expect(formatPace(1000, 359), isNot(contains(':60')));
      expect(formatPace(1000, 360), '6:00 /km');
    });
  });

  group('remainingMeters', () {
    test('counts down to zero and stops', () {
      expect(remainingMeters(5000, 0), 5000);
      expect(remainingMeters(5000, 4900), 100);
      expect(remainingMeters(5000, 5000), 0);
    });

    test('overshooting shows nothing left, not a negative', () {
      expect(remainingMeters(5000, 5200), 0);
    });
  });
}
