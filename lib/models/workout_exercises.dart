import 'package:liftr/models/catalog_exercises.dart';
import 'package:liftr/models/user_machines.dart';

class WorkoutExercises {
  final String? exerciseId;
  final String? sessionId;
  final String? catalogId;
  final CatalogExercises? catalogDetail;
  final int? orderIndex;
  final String? notes;
  final DateTime? createdAt;

  /// Which physical station this was done on, or null for "unspecified".
  ///
  /// Null is the honest and common case: it means nothing here distinguished
  /// one machine from another, which is true of everything logged before
  /// migration 012 and of every exercise where you only ever use one station.
  final String? machineId;

  /// The station itself, when the query joined it in.
  final UserMachine? machine;

  const WorkoutExercises({
    this.exerciseId,
    this.sessionId,
    this.catalogId,
    this.catalogDetail,
    this.orderIndex,
    this.notes,
    this.createdAt,
    this.machineId,
    this.machine,
  });

  String get name => catalogDetail?.name ?? 'Unknown exercise';

  factory WorkoutExercises.fromJson(Map<String, dynamic> j) => WorkoutExercises(
        exerciseId: j['exercise_id'] as String?,
        sessionId: j['session_id'] as String?,
        catalogId: j['catalog_id'] as String?,
        catalogDetail: j['catalog_detail'] == null
            ? null
            : CatalogExercises.fromJson(
                j['catalog_detail'] as Map<String, dynamic>),
        orderIndex: (j['order_index'] as num?)?.toInt(),
        notes: j['notes'] as String?,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.parse(j['created_at'] as String),
        machineId: j['machine_id'] as String?,
        machine: j['machine'] == null
            ? null
            : UserMachine.fromJson(j['machine'] as Map<String, dynamic>),
      );
}
