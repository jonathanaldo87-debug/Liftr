import 'package:flutter_test/flutter_test.dart';
import 'package:liftr/models/discipline.dart';
import 'package:liftr/models/workout_sessions.dart';
import 'package:liftr/services/workout_service.dart';

void main() {
  group('Discipline.fromJson', () {
    test('maps a disciplines row', () {
      final d = Discipline.fromJson({
        'discipline_key': 'running',
        'label': 'Running',
        'emoji': '🏃',
        'description': 'Distance & pace',
        'sort_order': 2,
      });
      expect(d.key, 'running');
      expect(d.label, 'Running');
      expect(d.description, 'Distance & pace');
      expect(d.sortOrder, 2);
      expect(d.isGym, isFalse);
    });

    test('survives a row seeded without the optional columns', () {
      final d = Discipline.fromJson({
        'discipline_key': 'swimming',
        'label': 'Swimming',
      });
      expect(d.emoji, '•');
      expect(d.description, '');
      expect(d.sortOrder, 0);
    });

    test('gym is the one key the app may special-case', () {
      final gym = Discipline.fromJson(
          {'discipline_key': 'gym', 'label': 'Gym', 'emoji': '🏋️'});
      expect(gym.isGym, isTrue);
      expect(Discipline.gymKey, 'gym');
    });

    test('equality is by key, so lookups and Set membership work', () {
      const a = Discipline(key: 'gym', label: 'Gym', emoji: '🏋️');
      const b = Discipline(key: 'gym', label: 'Different', emoji: '?');
      expect(a, b);
      expect({a, b}.length, 1);
    });
  });

  group('WorkoutSessions.discipline', () {
    test('defaults to gym when the column is absent', () {
      // Every session logged before migration 009 predates the column; they must
      // read as gym rather than null, or the home screen filters them all out.
      final s = WorkoutSessions.fromJson({
        'session_id': 'abc',
        'name': 'Push Day A',
        'session_date': '2026-07-16',
      });
      expect(s.discipline, Discipline.gymKey);
    });

    test('reads the column when present', () {
      final s = WorkoutSessions.fromJson({
        'session_id': 'abc',
        'session_date': '2026-07-16',
        'discipline': 'running',
      });
      expect(s.discipline, 'running');
    });
  });

  group('WorkoutSessions.isActive', () {
    test('defaults to ended when the column is absent', () {
      // Sessions predating migration 010 have no flag. Reading them as active
      // would mean every historical session claims to be the one you're on —
      // and more than one active row can't exist by design.
      final s = WorkoutSessions.fromJson({'session_id': 'abc'});
      expect(s.isActive, isFalse);
    });

    test('reads the flag when present', () {
      final active =
          WorkoutSessions.fromJson({'session_id': 'a', 'is_active': true});
      final ended =
          WorkoutSessions.fromJson({'session_id': 'b', 'is_active': false});
      expect(active.isActive, isTrue);
      expect(ended.isActive, isFalse);
    });
  });

  group('edit lock', () {
    // Mirrors _TodayTabState._canEdit. The rule: the session you're in is always
    // editable; anything else only while explicitly unlocked.
    bool canEdit(WorkoutSessions? s, String? unlockedId) {
      if (s?.sessionId == null) return false;
      if (s!.isActive) return true;
      return s.sessionId == unlockedId;
    }

    const active =
        WorkoutSessions(sessionId: 'a', discipline: 'gym', isActive: true);
    const ended =
        WorkoutSessions(sessionId: 'b', discipline: 'gym', isActive: false);

    test('the active session is editable without unlocking', () {
      expect(canEdit(active, null), isTrue);
    });

    test('a finished session is read-only by default', () {
      // The whole point: a stray tap must not rewrite last week's workout.
      expect(canEdit(ended, null), isFalse);
    });

    test('a finished session is editable once unlocked', () {
      expect(canEdit(ended, 'b'), isTrue);
    });

    test('unlocking one session does not unlock another', () {
      expect(canEdit(ended, 'someone-else'), isFalse);
    });

    test('relocking (unlock cleared on date/filter change) restores read-only',
        () {
      expect(canEdit(ended, 'b'), isTrue);
      expect(canEdit(ended, null), isFalse); // _relock()
    });

    test('no session is never editable', () {
      expect(canEdit(null, 'anything'), isFalse);
      expect(canEdit(const WorkoutSessions(), 'anything'), isFalse);
    });

    // Mirrors _toggleEdit: the chip flips Edit <-> Cancel rather than vanishing.
    String? toggle(String? unlockedId, String sessionId) =>
        unlockedId == sessionId ? null : sessionId;

    test('the chip toggles unlock on and back off', () {
      var unlocked = toggle(null, 'b'); // tap EDIT
      expect(canEdit(ended, unlocked), isTrue);

      unlocked = toggle(unlocked, 'b'); // tap CANCEL
      expect(canEdit(ended, unlocked), isFalse);
    });

    test('unlocking a second session releases the first', () {
      // Only one can be unlocked at a time — the state is a single id, so
      // switching sessions can't leave the previous one silently writable.
      var unlocked = toggle(null, 'b');
      unlocked = toggle(unlocked, 'c');
      expect(unlocked, 'c');
      expect(canEdit(ended, unlocked), isFalse);
    });
  });

  group('ActiveSessionExists', () {
    test('carries the blocking session so the UI can offer to end it', () {
      const active = WorkoutSessions(
        sessionId: 'gym-1',
        discipline: 'gym',
        isActive: true,
      );
      const e = ActiveSessionExists(active);

      // A typed exception, not a string to match on: the prompt needs the actual
      // session to name its discipline and date.
      expect(e.active.sessionId, 'gym-1');
      expect(e.active.discipline, 'gym');
      expect(e, isA<Exception>());
    });
  });
}
