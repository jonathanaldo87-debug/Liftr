import 'package:liftr/models/models.dart';

ExerciseSets? topSet(Iterable<ExerciseSets> sets) {
  ExerciseSets? best;
  for (final s in sets) {
    if (s.weightKg == null && s.reps == null) continue;
    if (best == null || _outranks(s, best)) best = s;
  }
  return best;
}

bool _outranks(ExerciseSets a, ExerciseSets b) {
  final aw = a.weightKg ?? -1;
  final bw = b.weightKg ?? -1;
  if (aw != bw) return aw > bw;
  return (a.reps ?? 0) > (b.reps ?? 0);
}

enum SetStructure {
  single,

  straight,

  ascending,

  descending,

  pyramid,

  mixed,
}

const double _weightEpsilon = 0.005;

SetStructure setStructure(Iterable<ExerciseSets> sets) {
  final ordered = [...sets]
    ..sort((a, b) => (a.setNumber ?? 0).compareTo(b.setNumber ?? 0));

  final weights = [
    for (final s in ordered)
      if (s.weightKg case final double w) w,
  ];

  if (weights.length < 2) return SetStructure.single;

  var rose = false;
  var fell = false;
  var roseAfterFalling = false;

  for (var i = 1; i < weights.length; i++) {
    final delta = weights[i] - weights[i - 1];
    if (delta > _weightEpsilon) {
      rose = true;
      if (fell) roseAfterFalling = true;
    } else if (delta < -_weightEpsilon) {
      fell = true;
    }
  }

  if (!rose && !fell) return SetStructure.straight;
  if (rose && !fell) return SetStructure.ascending;
  if (fell && !rose) return SetStructure.descending;
  return roseAfterFalling ? SetStructure.mixed : SetStructure.pyramid;
}

const double kDefaultIncrementKg = 2.5;

enum IncrementSource {
  assignedSetup,

  singleSetup,

  defaulted,

  ambiguous,

  bodyweight,
}

class ResolvedIncrement {
  final double? incrementKg;
  final IncrementSource source;

  final double? minWeightKg;

  const ResolvedIncrement(this.incrementKg, this.source, {this.minWeightKg});

  bool get isDefaulted =>
      source == IncrementSource.defaulted ||
      source == IncrementSource.ambiguous;

  bool get isAmbiguous => source == IncrementSource.ambiguous;
}

ResolvedIncrement resolveIncrement({
  required Iterable<ExerciseSetup> setups,
  String? assignedSetupId,
  required bool isBodyweight,
}) {
  if (isBodyweight) {
    return const ResolvedIncrement(null, IncrementSource.bodyweight);
  }

  final list = setups.toList();

  if (assignedSetupId != null) {
    for (final s in list) {
      if (s.setupId == assignedSetupId && s.isUsable) {
        return ResolvedIncrement(
          s.weightIncrementKg,
          IncrementSource.assignedSetup,
          minWeightKg: s.minWeightKg,
        );
      }
    }
  }

  final steps = <double>{
    for (final s in list)
      if (s.isUsable) s.weightIncrementKg!,
  };

  if (steps.isEmpty) {
    return const ResolvedIncrement(kDefaultIncrementKg, IncrementSource.defaulted);
  }
  if (steps.length == 1) {
    return ResolvedIncrement(steps.first, IncrementSource.singleSetup);
  }

  return const ResolvedIncrement(kDefaultIncrementKg, IncrementSource.ambiguous);
}

class RepRange {
  final int min;
  final int max;

  const RepRange(this.min, this.max);

  bool contains(int reps) => reps >= min && reps <= max;
}

const RepRange kDefaultRepRange = RepRange(8, 12);

enum ProgressionAction {
  increaseWeight,

  holdAddRep,

  decreaseWeight,

  increaseReps,

  deload,
}

enum ProgressionReason {
  hitTopOfRange,

  withinRange,

  belowRange,

  bodyweightAddReps,

  confidentProgression,

  gatheringData,

  confidentRegression,

  returningDeload,

  startingOver,

  bigJumpHoldReps,

  fatigueCollapse,
}

class ProgressionSuggestion {
  final ProgressionAction action;
  final double? suggestedWeightKg;
  final RepRange targetReps;
  final ProgressionReason reason;

  const ProgressionSuggestion({
    required this.action,
    required this.suggestedWeightKg,
    required this.targetReps,
    required this.reason,
  });

  ProgressionSuggestion copyWith({
    ProgressionAction? action,
    double? suggestedWeightKg,
    RepRange? targetReps,
    ProgressionReason? reason,
  }) =>
      ProgressionSuggestion(
        action: action ?? this.action,
        suggestedWeightKg: suggestedWeightKg ?? this.suggestedWeightKg,
        targetReps: targetReps ?? this.targetReps,
        reason: reason ?? this.reason,
      );
}

ProgressionSuggestion? coreSuggestion({
  required ExerciseSets topSet,
  required RepRange target,
  required double? increment,
}) {
  final reps = topSet.reps;
  if (reps == null) return null;

  if (increment == null) {
    return ProgressionSuggestion(
      action: ProgressionAction.increaseReps,
      suggestedWeightKg: null,
      targetReps: RepRange(reps + 1, reps + 2),
      reason: ProgressionReason.bodyweightAddReps,
    );
  }

  final weight = topSet.weightKg;
  if (weight == null) return null;

  if (reps >= target.max) {
    return ProgressionSuggestion(
      action: ProgressionAction.increaseWeight,
      suggestedWeightKg: weight + increment,
      targetReps: target,
      reason: ProgressionReason.hitTopOfRange,
    );
  }

  if (reps >= target.min) {
    return ProgressionSuggestion(
      action: ProgressionAction.holdAddRep,
      suggestedWeightKg: weight,
      targetReps: target,
      reason: ProgressionReason.withinRange,
    );
  }

  return ProgressionSuggestion(
    action: ProgressionAction.decreaseWeight,
    suggestedWeightKg: _easeDown(weight, increment),
    targetReps: target,
    reason: ProgressionReason.belowRange,
  );
}

double _easeDown(double weight, double increment) {
  final lowered = weight - increment;
  return lowered < increment ? increment : lowered;
}

enum _Outcome { hit, within, below }

_Outcome _outcomeOf(int reps, RepRange target) {
  if (reps >= target.max) return _Outcome.hit;
  if (reps < target.min) return _Outcome.below;
  return _Outcome.within;
}

ProgressionSuggestion? smoothedSuggestion({
  required ExerciseSets recentTop,
  ExerciseSets? previousTop,
  required RepRange target,
  required double? increment,
}) {
  final core = coreSuggestion(
    topSet: recentTop,
    target: target,
    increment: increment,
  );
  if (core == null) return null;

  final prevReps = previousTop?.reps;
  if (increment == null || prevReps == null) return core;

  final recentReps = recentTop.reps!;
  final weight = recentTop.weightKg!;

  final recent = _outcomeOf(recentReps, target);
  final previous = _outcomeOf(prevReps, target);

  if (recent == _Outcome.hit && previous == _Outcome.hit) {
    return ProgressionSuggestion(
      action: ProgressionAction.increaseWeight,
      suggestedWeightKg: weight + increment,
      targetReps: target,
      reason: ProgressionReason.confidentProgression,
    );
  }

  if (recent == _Outcome.below && previous == _Outcome.below) {
    return ProgressionSuggestion(
      action: ProgressionAction.decreaseWeight,
      suggestedWeightKg: _easeDown(weight, increment),
      targetReps: target,
      reason: ProgressionReason.confidentRegression,
    );
  }

  return ProgressionSuggestion(
    action: ProgressionAction.holdAddRep,
    suggestedWeightKg: weight,
    targetReps: target,
    reason: ProgressionReason.gatheringData,
  );
}

double roundToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  final w = (weight * 100).round();
  final inc = (increment * 100).round();
  final steps = (w / inc).round();
  return steps * inc / 100.0;
}

const int _layoffMinDays = 14;

double? _layoffFactor(int days) {
  if (days >= 60) return 0.75;
  if (days >= 30) return 0.85;
  if (days >= _layoffMinDays) return 0.90;
  return null;
}

ProgressionSuggestion? layoffAdjustment({
  required double? lastTopWeightKg,
  required int daysSinceLast,
  required RepRange target,
  required double? increment,
}) {
  if (increment == null) return null;

  final factor = _layoffFactor(daysSinceLast);
  if (factor == null) return null;
  if (lastTopWeightKg == null) return null;

  final deloaded = roundToIncrement(lastTopWeightKg * factor, increment);
  return ProgressionSuggestion(
    action: ProgressionAction.deload,
    suggestedWeightKg: deloaded < increment ? increment : deloaded,
    targetReps: target,
    reason: daysSinceLast >= 60
        ? ProgressionReason.startingOver
        : ProgressionReason.returningDeload,
  );
}

const double kBigJumpThreshold = 0.10;

const double kOutgrewRepFactor = 1.5;

ProgressionSuggestion applyBigJumpOverride(
  ProgressionSuggestion suggestion, {
  required double currentWeightKg,
  required double increment,
  required int achievedReps,
}) {
  if (suggestion.action != ProgressionAction.increaseWeight) return suggestion;
  if (currentWeightKg <= 0) return suggestion;
  if (increment <= currentWeightKg * kBigJumpThreshold) return suggestion;

  if (achievedReps >= suggestion.targetReps.max * kOutgrewRepFactor) {
    return suggestion;
  }

  return suggestion.copyWith(
    action: ProgressionAction.holdAddRep,
    suggestedWeightKg: currentWeightKg,
    reason: ProgressionReason.bigJumpHoldReps,
  );
}

const double _fatigueCollapseRatio = 0.5;

bool looksLikeFatigueCollapse(Iterable<ExerciseSets> sets) {
  if (setStructure(sets) != SetStructure.straight) return false;

  final ordered = [...sets]
    ..sort((a, b) => (a.setNumber ?? 0).compareTo(b.setNumber ?? 0));
  final reps = [
    for (final s in ordered)
      if (s.reps case final int r) r,
  ];
  if (reps.length < 2) return false;

  final first = reps.first;
  if (first <= 0) return false;
  final lowest = reps.reduce((a, b) => a < b ? a : b);
  return lowest <= first * _fatigueCollapseRatio;
}

double e1rm(double weightKg, int reps) => weightKg * (1 + reps / 30);

const int _plateauMinSessions = 3;

const double _plateauBandFraction = 0.03;

bool looksLikePlateau(Iterable<ExerciseSets> recentTopSets) {
  final scores = <double>[];
  double? currentWeight;
  for (final s in recentTopSets.take(5)) {
    final w = s.weightKg;
    final r = s.reps;
    if (w == null || r == null) continue;
    currentWeight ??= w;
    scores.add(e1rm(w, r));
    if (scores.length == 5) break;
  }

  if (scores.length < _plateauMinSessions || currentWeight == null) return false;

  final high = scores.reduce((a, b) => a > b ? a : b);
  final low = scores.reduce((a, b) => a < b ? a : b);
  return (high - low) < currentWeight * _plateauBandFraction;
}

ProgressionSuggestion? suggestProgression({
  required ExerciseSets recentTop,
  ExerciseSets? previousTop,
  int? daysSinceLast,
  Iterable<ExerciseSets> recentSets = const [],
  RepRange target = kDefaultRepRange,
  required double? increment,
  double? minWeightKg,
}) {
  if (increment == null) {
    return coreSuggestion(topSet: recentTop, target: target, increment: null);
  }

  if (daysSinceLast != null) {
    final layoff = layoffAdjustment(
      lastTopWeightKg: recentTop.weightKg,
      daysSinceLast: daysSinceLast,
      target: target,
      increment: increment,
    );
    if (layoff != null) return _finalize(layoff, increment, minWeightKg);
  }

  var suggestion = smoothedSuggestion(
    recentTop: recentTop,
    previousTop: previousTop,
    target: target,
    increment: increment,
  );
  if (suggestion == null) return null;

  final currentWeight = recentTop.weightKg;
  if (suggestion.action == ProgressionAction.increaseWeight &&
      currentWeight != null) {
    if (looksLikeFatigueCollapse(recentSets)) {
      suggestion = suggestion.copyWith(
        action: ProgressionAction.holdAddRep,
        suggestedWeightKg: currentWeight,
        reason: ProgressionReason.fatigueCollapse,
      );
    } else {
      suggestion = applyBigJumpOverride(
        suggestion,
        currentWeightKg: currentWeight,
        increment: increment,
        achievedReps: recentTop.reps ?? 0,
      );
    }
  }

  return _finalize(suggestion, increment, minWeightKg);
}

ProgressionSuggestion _finalize(
  ProgressionSuggestion s,
  double increment,
  double? minWeightKg,
) {
  final w = s.suggestedWeightKg;
  if (w == null) return s;

  var rounded = roundToIncrement(w, increment);
  final floor =
      (minWeightKg != null && minWeightKg > 0) ? minWeightKg : increment;
  if (rounded < floor) rounded = floor;

  return s.copyWith(suggestedWeightKg: rounded);
}
