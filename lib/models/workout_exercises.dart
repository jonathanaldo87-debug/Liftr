import 'package:liftr/models/catalog_exercises.dart';

class WorkoutExercises {
  final String? exerciseId;
  final String? sessionId;
  final String? catalogId;
  final CatalogExercises? catalogDetail;
  final int? orderIndex;
  final String? notes;
  final DateTime? createdAt;

  /// Which of this exercise's setups it was done on, or null for "not said".
  ///
  /// Null is the honest and common case. It is never filled in for you — see
  /// migration 017 for what happened the last time something was.
  final String? setupId;

  const WorkoutExercises({
    this.exerciseId,
    this.sessionId,
    this.catalogId,
    this.catalogDetail,
    this.orderIndex,
    this.notes,
    this.createdAt,
    this.setupId,
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
        setupId: j['setup_id'] as String?,
      );
}
