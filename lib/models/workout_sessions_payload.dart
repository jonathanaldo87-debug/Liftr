import 'discipline.dart';

class WorkoutSessionsPayload {
  final DateTime sessionDate;
  final String name;
  final String? notes;

  /// A `disciplines.discipline_key`. Defaults to gym so existing gym callers
  /// don't have to spell it out.
  final String discipline;

  final DateTime? updatedAt;

  const WorkoutSessionsPayload({
    required this.sessionDate,
    required this.name,
    this.notes,
    this.discipline = Discipline.gymKey,
    this.updatedAt,
  });
}
