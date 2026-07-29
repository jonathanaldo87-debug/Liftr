import 'discipline.dart';

class WorkoutSessionsPayload {
  final DateTime sessionDate;
  final String name;
  final String? notes;

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
