import 'package:flutter_test/flutter_test.dart';
import 'package:liftr/utils/increment_inference.dart';

void main() {
  group('inferIncrement', () {
    test('a stack only ever loaded in 5s reads as 5', () {
      expect(inferIncrement([40, 45, 50, 55]), 5);
    });

    test('one odd multiple is enough to prove the finer step', () {
      // 42.5 is impossible on a 5 kg stack, so the machine must do 2.5s —
      // even though every other reading would fit the coarser grid.
      expect(inferIncrement([40, 42.5, 45, 50]), 2.5);
    });

    test('1.25 steps survive the floating point that breaks a naive modulo', () {
      // 42.5 % 1.25 in doubles lands just short of zero; working in hundredths
      // is what keeps this from silently falling through to null.
      expect(inferIncrement([41.25, 42.5, 43.75, 45]), 1.25);
    });

    test('never infers a step the machine cannot actually do', () {
      // The property that matters: whatever comes back must divide every weight
      // ever logged, or a suggestion built on it is physically impossible.
      final histories = [
        [40.0, 45.0, 50.0],
        [40.0, 42.5, 45.0],
        [20.0, 30.0, 40.0],
        [41.25, 42.5, 45.0],
        [15.0, 22.5, 30.0, 37.5],
      ];

      for (final weights in histories) {
        final step = inferIncrement(weights);
        expect(step, isNotNull, reason: '$weights produced no estimate');
        for (final w in weights) {
          final remainder = (w * 100).round() % (step! * 100).round();
          expect(remainder, 0,
              reason: '$weights inferred $step, which cannot load $w');
        }
      }
    });

    test('errs coarse rather than fine when the evidence is thin', () {
      // Only ever loaded in 10s. The true step may well be 2.5, but nothing
      // here demonstrates it, and 10 is always achievable where 2.5 might not
      // be. Overshooting is the safe direction.
      expect(inferIncrement([40, 50, 60]), 10);
    });

    test('a single weight is not evidence', () {
      // 60 is a multiple of 10, 5, 2.5 and 1. Picking one would be invention.
      expect(inferIncrement([60]), isNull);
      expect(inferIncrement([60, 60, 60]), isNull);
    });

    test('says nothing rather than guessing when there is no history', () {
      expect(inferIncrement([]), isNull);
      expect(inferIncrement([null, null]), isNull);
    });

    test('ignores bodyweight and unlogged sets', () {
      // Zeroes are bodyweight reps, not a reading off a stack. Left in, they
      // would drag the GCD to whatever the remaining weights share.
      expect(inferIncrement([0, 40, 45, 0, 50]), 5);
      expect(inferIncrement([0, 0, 60]), isNull);
    });
  });

  group('inferMinWeight', () {
    test('is the lightest thing ever loaded', () {
      expect(inferMinWeight([40, 15, 50]), 15);
    });

    test('ignores bodyweight zeroes so the floor is a real pin', () {
      expect(inferMinWeight([0, 20, 35]), 20);
    });

    test('is null when nothing has been logged', () {
      expect(inferMinWeight([]), isNull);
      expect(inferMinWeight([0, null]), isNull);
    });
  });

  group('looksLikeTwoMachines', () {
    test('fires when a few fine readings sit among mostly coarse ones', () {
      // Mostly the 5 kg cable, twice on the 2.5 kg one. inferIncrement would
      // resolve this blend to 2.5, which the coarse machine cannot load.
      expect(
        looksLikeTwoMachines([40, 45, 50, 55, 60, 65, 42.5, 47.5]),
        isTrue,
      );
    });

    test('stays quiet for a stack that genuinely does 2.5s', () {
      // Odd multiples are routine here, not occasional — one machine, fine step.
      expect(
        looksLikeTwoMachines([40, 42.5, 45, 47.5, 50, 52.5]),
        isFalse,
      );
    });

    test('stays quiet for a plain 5 kg stack', () {
      expect(looksLikeTwoMachines([40, 45, 50, 55, 60]), isFalse);
    });

    test('needs enough history before it accuses anyone', () {
      expect(looksLikeTwoMachines([40, 42.5]), isFalse);
    });
  });
}
