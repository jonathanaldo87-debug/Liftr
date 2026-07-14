/// An exercise in the shared catalog.
///
/// Mirrors the curated list in `liftr_exercise_catalog.csv` (migration 007).
/// The free-exercise-db fields that used to live here — instructions, image
/// paths, force, mechanic, level — are gone with that catalog. Their columns
/// still exist in the database but nothing writes or reads them; 007's header
/// explains why.
class CatalogExercises {
  final String? catalogId;
  final String? name;

  /// Movement pattern: push / pull / legs / core.
  ///
  /// This used to hold a body part. Migration 007 redefined it — body part now
  /// lives in [muscleGroup], which is what the icons and subtitles key off.
  final String? category;

  /// Body part: chest / back / shoulders / biceps / triceps / quads /
  /// hamstrings / glutes / calves / abs / lower_back.
  final String? muscleGroup;

  /// barbell / dumbbell / machine / cable / bodyweight.
  final String? equipment;

  /// Multi-joint (squat, bench) rather than single-joint (curl, lateral raise).
  final bool? isCompound;

  final bool? isGlobal;
  final String? createdBy;
  final String? createdAt;

  const CatalogExercises({
    this.catalogId,
    this.name,
    this.category,
    this.muscleGroup,
    this.equipment,
    this.isCompound,
    this.isGlobal,
    this.createdBy,
    this.createdAt,
  });

  factory CatalogExercises.fromJson(Map<String, dynamic> j) => CatalogExercises(
        catalogId: j['catalog_id'] as String?,
        name: j['name'] as String?,
        category: j['category'] as String?,
        muscleGroup: j['muscle_group'] as String?,
        equipment: j['equipment'] as String?,
        isCompound: j['is_compound'] as bool?,
        isGlobal: j['is_global'] as bool?,
        createdBy: j['created_by'] as String?,
        createdAt: j['created_at'] as String?,
      );
}
