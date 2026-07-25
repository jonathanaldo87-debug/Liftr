/// The rules that turn a user's recent sets into a weight/rep hint, kept pure so
/// the decision can be tested without a database, a clock, or a logged-in user.
///
/// Pure: everything here is a function of its arguments. The IO that feeds these
/// — fetching the last sessions, the setups, the catalog — lives in
/// `services/progression_service.dart`, the same split as
/// `increment_inference.dart` and its service.
///
/// This file is step 1–2 of the feature: identifying the top set, naming the set
/// structure, and resolving which weight increment applies. The up/stay/down
/// rule that consumes them is layered on in later steps.

import 'package:liftr/models/models.dart';

// ── Top set ───────────────────────────────────────────────────────────────

/// The set a session is judged by: the heaviest, and among equal weights the
/// one with the most reps.
///
/// Heaviest because that's the set that proves the user got stronger; more reps
/// breaks the tie because 40×10 is a better day than 40×8. Backoff sets after it
/// don't enter the up/down decision (see the feature spec), so they aren't
/// considered here either.
///
/// Null-safe on both fields. A set with no recorded weight ranks below any
/// weighted set — an unweighted row can't be the "heaviest" — which leaves
/// bodyweight exercises (every weight null) falling through to a pure rep
/// comparison, so this still names a top set for them. Returns null only when
/// there is nothing to rank: an empty list, or rows with neither weight nor
/// reps.
ExerciseSets? topSet(Iterable<ExerciseSets> sets) {
  ExerciseSets? best;
  for (final s in sets) {
    if (s.weightKg == null && s.reps == null) continue; // an empty row, no data
    if (best == null || _outranks(s, best)) best = s;
  }
  return best;
}

/// True when [a] is a heavier set than [b], or an equally heavy one with more
/// reps. `-1` stands in for "no weight recorded" so a null-weight set sorts
/// below any real load rather than above it; real weights are never negative.
bool _outranks(ExerciseSets a, ExerciseSets b) {
  final aw = a.weightKg ?? -1;
  final bw = b.weightKg ?? -1;
  if (aw != bw) return aw > bw;
  return (a.reps ?? 0) > (b.reps ?? 0);
}

// ── Set structure ─────────────────────────────────────────────────────────

/// The shape of a session's weights across its sets. Context for the user; it
/// never changes the decision, which always runs off the top set.
enum SetStructure {
  /// Fewer than two weighted sets — nothing to compare.
  single,

  /// Every set at the same weight.
  straight,

  /// Weight climbing set to set (pyramid up / ramp).
  ascending,

  /// Weight falling set to set (drop sets).
  descending,

  /// Up to a peak, then down — a single hump.
  pyramid,

  /// Anything else: a valley, or weights that wander.
  mixed,
}

/// Weights within a hundredth of a kg are the same rung. Without this, numeric
/// noise off Postgres (40.0 vs 40.00000001) would read as a phantom increase —
/// the same floating-point trap `increment_inference.dart` sidesteps with
/// integer hundredths.
const double _weightEpsilon = 0.005;

/// Names the [sets]' structure from their weights in set order.
///
/// Sorts by set number defensively rather than trusting the caller's order, and
/// skips sets with no weight — an unlogged weight can't be placed on the ramp,
/// but it shouldn't collapse the whole reading to [SetStructure.single] either.
SetStructure setStructure(Iterable<ExerciseSets> sets) {
  final ordered = [...sets]
    ..sort((a, b) => (a.setNumber ?? 0).compareTo(b.setNumber ?? 0));

  final weights = [
    for (final s in ordered)
      if (s.weightKg case final double w) w,
  ];

  if (weights.length < 2) return SetStructure.single;

  var rose = false; // saw a step up anywhere
  var fell = false; // saw a step down anywhere
  var roseAfterFalling = false; // went back up after a drop — not a clean hump

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
  // Both directions: a single up-then-down hump is a pyramid; anything that
  // rises again after falling (a valley, or a zig-zag) is mixed.
  return roseAfterFalling ? SetStructure.mixed : SetStructure.pyramid;
}

// ── Increment resolution ──────────────────────────────────────────────────

/// The step used when nothing better is known: the plate jump most gyms have.
const double kDefaultIncrementKg = 2.5;

/// Where a resolved increment came from — which decides how the hint explains
/// itself, and whether it nudges the user to record a setup.
enum IncrementSource {
  /// The setup the logged exercise was actually done on (`setup_id`).
  assignedSetup,

  /// The one usable setup that applies, or several that agree on the step.
  singleSetup,

  /// No usable setup exists; fell back to [kDefaultIncrementKg].
  defaulted,

  /// Several usable setups disagree on the step and nothing records which was
  /// used, so the default stands — but the hint should say so and offer to fix
  /// it, because the user *can* make this exact.
  ambiguous,

  /// A bodyweight exercise: there is no external load to step, so progression is
  /// rep-based and the increment is null rather than defaulted.
  bodyweight,
}

/// A weight increment together with the story of how it was chosen.
class ResolvedIncrement {
  final double? incrementKg;
  final IncrementSource source;

  const ResolvedIncrement(this.incrementKg, this.source);

  /// The value stands in for a real setup — worth telling the user they can
  /// improve it. True for both the plain fallback and the ambiguous one.
  bool get isDefaulted =>
      source == IncrementSource.defaulted ||
      source == IncrementSource.ambiguous;

  /// Specifically the two-stacks case: setups exist but disagree, so the hint
  /// says "assign which stack for a sharper suggestion" rather than "set one up".
  bool get isAmbiguous => source == IncrementSource.ambiguous;
}

/// Works out the weight step to size a suggestion by, following the priority the
/// spec lays out:
///
///   1. the setup the set was logged on ([assignedSetupId]), if usable;
///   2. otherwise the applicable setups — one, or several that agree;
///   3. otherwise [kDefaultIncrementKg].
///
/// Bodyweight short-circuits to a null increment: there's nothing to step.
///
/// "Usable" means the setup has a real, positive step ([ExerciseSetup.isUsable])
/// — an unconfirmed setup with a null increment is not evidence, exactly as the
/// inference layer treats a null.
ResolvedIncrement resolveIncrement({
  required Iterable<ExerciseSetup> setups,
  String? assignedSetupId,
  required bool isBodyweight,
}) {
  if (isBodyweight) {
    return const ResolvedIncrement(null, IncrementSource.bodyweight);
  }

  final list = setups.toList();

  // 1. What the set was actually done on wins outright — it's the one case with
  // no ambiguity to resolve.
  if (assignedSetupId != null) {
    for (final s in list) {
      if (s.setupId == assignedSetupId && s.isUsable) {
        return ResolvedIncrement(s.weightIncrementKg, IncrementSource.assignedSetup);
      }
    }
  }

  // 2. The setups whose step is actually known.
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

  // Several usable setups, differing steps, and no record of which was used:
  // the two-cable-stacks problem. Guessing here is exactly what migrations
  // 012–018 exist to stop, so default and flag it instead.
  return const ResolvedIncrement(kDefaultIncrementKg, IncrementSource.ambiguous);
}

// ── The core up / stay / down rule ────────────────────────────────────────

/// The reps a set aims to land in. Global default for now; the spec has this
/// moving to per-exercise storage later, which is why it's a value object
/// rather than two loose ints.
class RepRange {
  final int min;
  final int max;

  const RepRange(this.min, this.max);

  bool contains(int reps) => reps >= min && reps <= max;
}

/// 8–12 is the default working range for most gym exercises.
const RepRange kDefaultRepRange = RepRange(8, 12);

/// What the hint tells the user to do next time.
enum ProgressionAction {
  /// Got the reps — add a weight step.
  increaseWeight,

  /// In range but not at the top — same weight, chase one more rep.
  holdAddRep,

  /// Fell short of the range — ease the weight down a step.
  decreaseWeight,

  /// Bodyweight: no load to change, so add reps.
  increaseReps,

  /// Coming back from time off — restart at a reduced weight.
  deload,
}

/// Why the hint says what it says — kept separate from [ProgressionAction]
/// because later refinements reach the same action for different reasons (a
/// hold can come from the core range, a too-big jump, or fatigue).
enum ProgressionReason {
  /// Hit or beat the top of the range.
  hitTopOfRange,

  /// Landed inside the range, below the top.
  withinRange,

  /// Came in under the range.
  belowRange,

  /// Bodyweight progression, which is always rep-based.
  bodyweightAddReps,

  /// Two sessions in a row hit the top — add weight with confidence.
  confidentProgression,

  /// One good day or one bad day, but not two — hold and gather another point.
  gatheringData,

  /// Two sessions in a row fell short — drop the weight with confidence.
  confidentRegression,

  /// Back after two weeks to two months off — come back a little lighter.
  returningDeload,

  /// Back after two months or more — effectively starting the lift over.
  startingOver,

  /// The rule said progress, but one step is too big a jump at this weight —
  /// earn more reps here first.
  bigJumpHoldReps,

  /// Straight sets whose reps collapsed set to set — the first set was too
  /// heavy, so hold rather than progress.
  fatigueCollapse,
}

/// A single next-time suggestion. [suggestedWeightKg] is null only for
/// bodyweight, where [targetReps] carries the "+1–2 reps" goal instead.
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

/// The core rule, run off one session's top set:
///
///   reps ≥ range max  → add a step, aim for the same range again
///   reps in the range → hold, aim for one more rep
///   reps < range min  → drop a step
///
/// Rep count alone drives it — no effort input. This is the un-refined decision:
/// two-session smoothing, time-off scaling, the big-jump override and rounding
/// are layered on top in later steps and may overrule the weight it returns.
///
/// Returns null when there's nothing to decide from — a top set with no rep
/// count, or a weighted exercise whose top set has no recorded weight. Null
/// reads as "no hint", the same as having no history at all.
///
/// A null [increment] means bodyweight: the suggestion becomes "add 1–2 reps"
/// rather than a weight change.
ProgressionSuggestion? coreSuggestion({
  required ExerciseSets topSet,
  required RepRange target,
  required double? increment,
}) {
  final reps = topSet.reps;
  if (reps == null) return null; // no rep count — nothing to judge

  // Bodyweight: nothing to load, so progress by reps. The next goal is this
  // set's reps plus one or two.
  if (increment == null) {
    return ProgressionSuggestion(
      action: ProgressionAction.increaseReps,
      suggestedWeightKg: null,
      targetReps: RepRange(reps + 1, reps + 2),
      reason: ProgressionReason.bodyweightAddReps,
    );
  }

  final weight = topSet.weightKg;
  if (weight == null) return null; // weighted lift, but no weight to step from

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

  // Below the range: too heavy. Ease down a step, but never below one step —
  // a suggestion of zero or less is nonsense. The stack's real floor
  // (min_weight_kg) is applied later, once the setup is in hand.
  return ProgressionSuggestion(
    action: ProgressionAction.decreaseWeight,
    suggestedWeightKg: _easeDown(weight, increment),
    targetReps: target,
    reason: ProgressionReason.belowRange,
  );
}

/// One step down, but never below a single step.
double _easeDown(double weight, double increment) {
  final lowered = weight - increment;
  return lowered < increment ? increment : lowered;
}

// ── Two-session smoothing ─────────────────────────────────────────────────

/// Where a session's top set landed against the range — the unit smoothing
/// reasons over.
enum _Outcome { hit, within, below }

_Outcome _outcomeOf(int reps, RepRange target) {
  if (reps >= target.max) return _Outcome.hit;
  if (reps < target.min) return _Outcome.below;
  return _Outcome.within;
}

/// The core rule, steadied against the previous session so a suggestion doesn't
/// swing on one outlier day:
///
///   both sessions hit the top   → confident progression, add a step
///   both fell below the range   → confident regression, drop a step
///   anything mixed              → hold, and gather another data point
///
/// The reference weight is the most recent session's top-set weight — what the
/// user actually last lifted. Only the *decision* is smoothed; the number a
/// step moves from is still the latest one.
///
/// Falls back to the single-session [coreSuggestion] when there's nothing to
/// smooth against: only one session, a previous session with no rep count, or a
/// bodyweight exercise (no weight to steady). Returns null on the same
/// no-signal cases as [coreSuggestion].
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

  // Bodyweight has no weight to steady, and a null previous rep count is not a
  // second data point — either way the single-session decision stands.
  final prevReps = previousTop?.reps;
  if (increment == null || prevReps == null) return core;

  // core != null with a non-null increment guarantees both of these are set.
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

  // One good day or one bad day, but not two: hold the weight and let the next
  // session break the tie. This is what stops chasing a fluke or panicking on a
  // single miss.
  return ProgressionSuggestion(
    action: ProgressionAction.holdAddRep,
    suggestedWeightKg: weight,
    targetReps: target,
    reason: ProgressionReason.gatheringData,
  );
}

// ── Rounding to achievable weights ────────────────────────────────────────

/// Snaps [weight] to the nearest multiple of [increment], so a suggestion only
/// ever names a weight the equipment can actually make.
///
/// Works in integer hundredths for the same reason as `increment_inference.dart`:
/// `38.25 / 2.5` in doubles can land a hair off and round the wrong way. Halves
/// round up (away from zero), the conventional direction. A non-positive
/// increment has nothing to snap to, so the weight passes through untouched.
double roundToIncrement(double weight, double increment) {
  if (increment <= 0) return weight;
  final w = (weight * 100).round();
  final inc = (increment * 100).round();
  final steps = (w / inc).round();
  return steps * inc / 100.0;
}

// ── Time-off adjustment ───────────────────────────────────────────────────

/// Below this many days off, nothing is adjusted — the normal rule runs.
const int _layoffMinDays = 14;

/// The fraction of the last top-set weight to come back at, by gap length, or
/// null when the gap is too short to deload. Boundaries resolve to the deeper
/// deload: 30 days is 85%, 60 days is 75%.
double? _layoffFactor(int days) {
  if (days >= 60) return 0.75;
  if (days >= 30) return 0.85;
  if (days >= _layoffMinDays) return 0.90;
  return null;
}

/// A layoff deload, applied *before* the up/down rule and short-circuiting it:
/// after a couple of weeks off, last session's reps aren't a basis to progress
/// or regress from, so the suggestion becomes "come back at a lighter weight"
/// rather than a comparison.
///
///   14–30 days → 90% of the last top set
///   30–60 days → 85%
///   60+  days → 75%, framed as starting over
///
/// The weight is rounded to a loadable value and floored at one step. Returns
/// null when there's nothing to deload — a gap under two weeks (run the normal
/// rule), a bodyweight exercise (no weight to scale), or no recorded last
/// weight.
ProgressionSuggestion? layoffAdjustment({
  required double? lastTopWeightKg,
  required int daysSinceLast,
  required RepRange target,
  required double? increment,
}) {
  if (increment == null) return null; // bodyweight: no load to deload

  final factor = _layoffFactor(daysSinceLast);
  if (factor == null) return null; // fresh enough — the normal rule applies
  if (lastTopWeightKg == null) return null; // nothing to scale

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

// ── Big-jump override ─────────────────────────────────────────────────────

/// A step worth more than this fraction of the current weight is too coarse to
/// force a jump on. Loosened from 5% to 10% to match standard advice — a 2.5 kg
/// step is fine down to 25 kg, and only suppressed below that.
const double kBigJumpThreshold = 0.10;

/// Reps at or beyond this multiple of the range max mean the lift has been
/// outgrown outright — take the step even if it's a big one. Without this,
/// light isolation work where the step is already the smallest the equipment
/// makes (2.5 kg on a 12.5 kg dumbbell) would hold for reps forever, since
/// there is no finer jump to bridge the gap with.
const double kOutgrewRepFactor = 1.5;

/// Suppresses a weight increase when one step is too large a leap at the current
/// weight — a 5 kg jump on a 30 kg lift is a 17% overload, more than most lifts
/// absorb in one go. The advice becomes "hold and earn more reps first".
///
/// The exception is a lift plainly outgrown: [achievedReps] at or past
/// [kOutgrewRepFactor]× the range max takes the step regardless, because
/// holding for still more reps on a 2.5 kg-minimum lift never resolves.
///
/// Only touches [ProgressionAction.increaseWeight]; every other action passes
/// through. [currentWeightKg] is what the user is lifting now — the weight the
/// step would be added to, not the already-increased suggestion.
ProgressionSuggestion applyBigJumpOverride(
  ProgressionSuggestion suggestion, {
  required double currentWeightKg,
  required double increment,
  required int achievedReps,
}) {
  if (suggestion.action != ProgressionAction.increaseWeight) return suggestion;
  if (currentWeightKg <= 0) return suggestion;
  if (increment <= currentWeightKg * kBigJumpThreshold) return suggestion;

  // Outgrew it: reps far past the range mean the step, coarse as it is, is the
  // only way up — so take it rather than holding indefinitely.
  if (achievedReps >= suggestion.targetReps.max * kOutgrewRepFactor) {
    return suggestion;
  }

  return suggestion.copyWith(
    action: ProgressionAction.holdAddRep,
    suggestedWeightKg: currentWeightKg,
    reason: ProgressionReason.bigJumpHoldReps,
  );
}

// ── Straight-set fatigue collapse ─────────────────────────────────────────

/// At or below this fraction of the first set's reps counts as a sharp drop.
const double _fatigueCollapseRatio = 0.5;

/// Whether a session was straight sets whose reps fell off a cliff — 12, 6, 4 on
/// the same weight. That pattern says the first set was too heavy to sustain,
/// not that the lift is ready to go up, so a progression built on the top set
/// would be misled by it.
///
/// Straight sets only: on descending or pyramid sets a rep drop is the plan, not
/// fatigue. Needs at least two sets with rep counts to see a drop at all.
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

// ── Estimated one-rep max and plateau ─────────────────────────────────────

/// Epley's estimate: the weight a set is "worth" as a one-rep max, so sets at
/// different weight/rep combos can be compared. Used only for plateau detection
/// and progress tracking, never for the up/down decision.
double e1rm(double weightKg, int reps) => weightKg * (1 + reps / 30);

/// Below this many sessions with data, there isn't enough to call a plateau.
const int _plateauMinSessions = 3;

/// A plateau is estimated strength that hasn't moved. Within this fraction of
/// the current top-set weight, across the recent sessions, counts as flat.
const double _plateauBandFraction = 0.03;

/// Whether the last few sessions' estimated max has gone flat.
///
/// [recentTopSets] are the top set of each recent session, newest first (up to
/// five). Compares the spread of their e1RMs against 3% of the current top-set
/// weight: a spread tighter than that band is a plateau.
///
/// Needs at least [_plateauMinSessions] sessions with both a weight and reps —
/// calling a plateau off one or two data points would fire on noise.
bool looksLikePlateau(Iterable<ExerciseSets> recentTopSets) {
  final scores = <double>[];
  double? currentWeight;
  for (final s in recentTopSets.take(5)) {
    final w = s.weightKg;
    final r = s.reps;
    if (w == null || r == null) continue;
    currentWeight ??= w; // first with data is the most recent
    scores.add(e1rm(w, r));
    if (scores.length == 5) break;
  }

  if (scores.length < _plateauMinSessions || currentWeight == null) return false;

  final high = scores.reduce((a, b) => a > b ? a : b);
  final low = scores.reduce((a, b) => a < b ? a : b);
  return (high - low) < currentWeight * _plateauBandFraction;
}

// ── The composed suggestion ───────────────────────────────────────────────

/// The whole rule, in the order the refinements stack:
///
///   1. bodyweight → rep-based, and nothing else applies;
///   2. a layoff (14+ days) → deload, short-circuiting the comparison;
///   3. otherwise the two-session smoothed up/down decision;
///   4. a straight-set fatigue collapse or too-big a jump downgrades an
///      increase to a hold;
///   5. the weight is rounded to a loadable value and floored.
///
/// This is the single entry the UI layer calls. It stays pure — the service
/// gathers the inputs (recent sessions, the gap in days, the increment) and
/// hands them here.
///
/// [minWeightKg] is the bottom of the stack when known, so a decrease can't
/// point below it; without it the floor is one step. Returns null on the same
/// no-signal cases as the rules it composes.
ProgressionSuggestion? suggestProgression({
  required ExerciseSets recentTop,
  ExerciseSets? previousTop,
  int? daysSinceLast,
  Iterable<ExerciseSets> recentSets = const [],
  RepRange target = kDefaultRepRange,
  required double? increment,
  double? minWeightKg,
}) {
  // Bodyweight: rep-based only, no weight refinements to apply.
  if (increment == null) {
    return coreSuggestion(topSet: recentTop, target: target, increment: null);
  }

  // A layoff replaces the comparison outright.
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
    // Collapse first, so its "first set was too heavy" reason wins over the
    // generic big-jump note when both would fire.
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

/// Rounds a suggestion's weight to a loadable value and floors it — at the
/// stack's bottom when known, otherwise at one step.
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
