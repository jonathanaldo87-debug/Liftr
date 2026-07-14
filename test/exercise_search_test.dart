import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liftr/models/catalog_exercises.dart';
import 'package:liftr/utils/exercise_search.dart';
import 'package:liftr/utils/format.dart';

CatalogExercises ex(
  String name, {
  required String category,
  required String muscle,
  required String equipment,
}) =>
    CatalogExercises(
      catalogId: name,
      name: name,
      category: category,
      muscleGroup: muscle,
      equipment: equipment,
    );

void main() {
  // A slice of the curated catalog, spelled exactly as the CSV spells it.
  // Note `category` is a movement pattern here (push/pull/legs/core), not a
  // body part — that lives in `muscle`.
  final catalog = [
    ex('Barbell Bench Press',
        category: 'push', muscle: 'chest', equipment: 'barbell'),
    ex('Chest Press Machine',
        category: 'push', muscle: 'chest', equipment: 'machine'),
    ex('Incline Chest Press Machine',
        category: 'push', muscle: 'chest', equipment: 'machine'),
    ex('Pec Deck', category: 'push', muscle: 'chest', equipment: 'machine'),
    ex('Cable Fly', category: 'push', muscle: 'chest', equipment: 'cable'),
    ex('Overhead Barbell Press',
        category: 'push', muscle: 'shoulders', equipment: 'barbell'),
    ex('Barbell Curl',
        category: 'pull', muscle: 'biceps', equipment: 'barbell'),
    ex('Dumbbell Curl',
        category: 'pull', muscle: 'biceps', equipment: 'dumbbell'),
    ex('Cable Hammer Curl',
        category: 'pull', muscle: 'biceps', equipment: 'cable'),
    ex('Lat Pulldown', category: 'pull', muscle: 'back', equipment: 'cable'),
    ex('Romanian Deadlift',
        category: 'legs', muscle: 'hamstrings', equipment: 'barbell'),
    ex('Back Squat', category: 'legs', muscle: 'quads', equipment: 'barbell'),
    ex('Push Up', category: 'push', muscle: 'chest', equipment: 'bodyweight'),
    ex('Back Extension',
        category: 'core', muscle: 'lower_back', equipment: 'bodyweight'),
  ];

  final search = ExerciseSearch(catalog);
  List<String> names(String q) => search.search(q).map((e) => e.name!).toList();

  group('against the real catalog CSV', () {
    // Reads the source-of-truth CSV rather than a fixture, so a catalog edit
    // that breaks search shows up here instead of at the rack. Path is relative
    // to the package root, which is where `flutter test` runs from.
    final file = File('db/liftr_exercise_catalog_v2.csv');

    final lines = file.readAsLinesSync()
      ..removeAt(0); // header

    final real = lines.where((l) => l.trim().isNotEmpty).map((line) {
      final f = line.split(',');
      // A quoted field containing a comma would split into more than 5 and
      // silently shift every column. Fail loudly instead of testing garbage.
      if (f.length != 5) {
        fail('CSV line does not have 5 plain fields — it may contain a quoted '
            'comma, which this parser cannot handle: $line');
      }
      return ex(f[0], category: f[1], muscle: f[2], equipment: f[3]);
    }).toList();

    final realSearch = ExerciseSearch(real);

    List<String> hits(String q) =>
        realSearch.search(q).map((e) => e.name!).toList();

    test('the catalog is fully loaded', () {
      expect(real.length, 219);
    });

    test('the machines that started all this are findable', () {
      expect(hits('chest press machine').first, 'Chest Press Machine');
      expect(hits('upper chest machine'), contains('Incline Chest Press Machine'));
      expect(hits('pec deck').first, 'Pec Deck');
    });

    test('every exercise is reachable by its own name', () {
      final unreachable = real
          .where((e) => !realSearch.search(e.name!, limit: 500).contains(e))
          .map((e) => e.name)
          .toList();
      expect(unreachable, isEmpty);
    });

    test('shorthand still resolves against the real data', () {
      expect(hits('rdl'), contains('Romanian Deadlift'));
      expect(hits('traps'), contains('Barbell Shrug'));
      expect(hits('lats'), contains('Lat Pulldown'));
    });
  });

  group('the search that started this', () {
    test('"chest press machine" finds it — a plain substring filter found nothing',
        () {
      final got = names('chest press machine');
      expect(got, contains('Chest Press Machine'));
      // No "machine" anywhere on the barbell press, so it correctly drops out.
      expect(got, isNot(contains('Barbell Bench Press')));
    });

    test('word order does not matter', () {
      expect(names('machine chest press'), equals(names('chest press machine')));
    });

    test('"upper chest" reaches the incline machine', () {
      expect(names('upper chest'), contains('Incline Chest Press Machine'));
    });
  });

  group('gym shorthand', () {
    test('"db curl" finds the dumbbell curl, not the barbell one', () {
      final got = names('db curl');
      expect(got, contains('Dumbbell Curl'));
      expect(got, isNot(contains('Barbell Curl')));
    });

    test('"rdl" reaches the Romanian deadlift', () {
      expect(names('rdl'), contains('Romanian Deadlift'));
    });

    test('"ohp" reaches the overhead press', () {
      expect(names('ohp'), contains('Overhead Barbell Press'));
    });

    test('"bis" and "pecs" resolve to muscle groups', () {
      expect(names('bis'), contains('Barbell Curl'));
      expect(names('pecs'), contains('Cable Fly'));
    });
  });

  group('names the catalog now spells literally', () {
    // "pec deck" used to be rewritten to "butterfly" for the old catalog.
    // The curated one has a real Pec Deck, so the rewrite had to go or it
    // would have broken the exact match.
    test('"pec deck" finds Pec Deck', () {
      expect(names('pec deck').first, 'Pec Deck');
    });

    test('"hammer strength" still reaches machines', () {
      expect(names('hammer strength chest'), contains('Chest Press Machine'));
    });

    test('"hammer curl" is untouched by that', () {
      expect(names('hammer curl'), contains('Cable Hammer Curl'));
    });
  });

  group('ranking', () {
    test('the exact name wins over the longer variant', () {
      expect(names('chest press machine').first, 'Chest Press Machine');
    });

    test('a name match beats an equipment-only match', () {
      final got = names('curl');
      expect(got, contains('Barbell Curl'));
      expect(got.first.toLowerCase(), contains('curl'));
    });

    test('browsing by movement pattern works', () {
      expect(names('legs'), contains('Back Squat'));
      expect(names('legs'), isNot(contains('Barbell Bench Press')));
    });
  });

  group('display formatting', () {
    test('title-cases catalog values', () {
      expect(titleCase('bodyweight'), 'Bodyweight');
      expect(titleCase('machine'), 'Machine');
      // Underscores are separators, not characters anyone wants to read.
      expect(titleCase('lower_back'), 'Lower Back');
    });

    test('drops empty parts instead of leaving a dangling separator', () {
      expect(detailLine(['machine', null]), 'Machine');
      expect(detailLine([null, '']), '');
      expect(detailLine(['machine', 'chest']), 'Machine · Chest');
    });

    test('icons key off muscle group, since category is now push/pull/legs', () {
      expect(exerciseEmoji('push', 'chest'), '🏋️');
      expect(exerciseEmoji('pull', 'biceps'), '💪');
      expect(exerciseEmoji('legs', 'glutes'), '🍑');
      expect(exerciseEmoji('core', 'abs'), '🧘');
      // Falls back to the movement pattern when the muscle is unknown.
      expect(exerciseEmoji('legs', null), '🦵');
    });

    test('the muscle groups v2 added have icons of their own', () {
      // Without these they would fall through to the category default, and
      // every forearm and neck exercise would wear the wrong icon.
      expect(exerciseEmoji('pull', 'forearms'), '💪');
      expect(exerciseEmoji('push', 'neck'), '🙆');
    });
  });
}
