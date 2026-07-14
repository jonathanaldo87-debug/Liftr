class CatalogExercises {
  final String? catalogId;
  final String? name;
  final String? category;
  final String? muscleGroup;
  final bool? isGlobal;
  final String? createdBy;
  final String? createdAt;

  const CatalogExercises({
    this.catalogId,
    this.name,
    this.category,
    this.muscleGroup,
    this.isGlobal,
    this.createdBy,
    this.createdAt,
  });

  factory CatalogExercises.fromJson(Map<String, dynamic> j) => CatalogExercises(
        catalogId: j['catalog_id'] as String?,
        name: j['name'] as String?,
        category: j['category'] as String?,
        muscleGroup: j['muscle_group'] as String?,
        isGlobal: j['is_global'] as bool?,
        createdBy: j['created_by'] as String?,
        createdAt: j['created_at'] as String?,
      );
}
