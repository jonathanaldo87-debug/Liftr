import 'package:liftr/models/catalog_exercises.dart';

class WorkoutExercises {
  final String? exerciseId;
  final String? sessionId;
  final String? catalogId;
  final CatalogExercises? catalogDetail;
  final int? orderIndex;
  final DateTime? createdAt;

  const WorkoutExercises({
    this.exerciseId,
    this.sessionId,
    this.catalogId,
    this.catalogDetail,
    this.orderIndex,
    this.createdAt,
  });

  factory WorkoutExercises.fromJson(Map<String, dynamic> j) => WorkoutExercises(
        exerciseId: j['exercise_id'] as String?,
        sessionId: j['session_id'] as String?,
        catalogId: j['catalog_id'] as String?,
        catalogDetail: j['catalog_detail'] == null ? null : CatalogExercises.fromJson(j['catalog_detail'] as Map<String, dynamic>),
        orderIndex: j['order_index'] as int?,
        createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at'] as String),
      );
}
