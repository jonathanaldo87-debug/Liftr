import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:liftr/utils/username.dart';

void main() {
  group('generateUsername', () {
    test('is two words and a 4-digit number', () {
      final name = generateUsername(Random(7));
      expect(name, matches(RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+ \d{4}$')));
    });

    test('the number is always 4 digits — never 0 or 5 of them', () {
      // A plain nextInt(10000) would happily produce "Iron Bear 7", which looks
      // broken next to "Iron Bear 4821".
      for (var seed = 0; seed < 200; seed++) {
        final digits = generateUsername(Random(seed)).split(' ').last;
        expect(digits.length, 4, reason: 'seed $seed produced "$digits"');
      }
    });

    test('varies across calls', () {
      final names = List.generate(50, (_) => generateUsername()).toSet();
      // 16 x 16 x 9000 combinations, so 50 draws colliding into a handful would
      // mean the generator is broken.
      expect(names.length, greaterThan(40));
    });
  });

  group('initialsFromUsername', () {
    test('takes the first letter of the first two words', () {
      expect(initialsFromUsername('Swift Falcon 4821'), 'SF');
      expect(initialsFromUsername('Iron Ox 1000'), 'IO');
    });

    test('ignores the number when picking letters', () {
      // Splitting naively on spaces and taking words[0] and words[1] would be
      // fine, but a one-word name must not reach for a digit.
      expect(initialsFromUsername('Iron 4821'), 'IR');
    });

    test('survives junk rather than crashing the avatar', () {
      expect(initialsFromUsername(''), '?');
      expect(initialsFromUsername('   '), '?');
      expect(initialsFromUsername('4821'), '?');
      expect(initialsFromUsername('X'), 'X');
    });
  });
}
