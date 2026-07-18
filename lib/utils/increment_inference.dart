/// Working out what a weight stack's step is from the weights you've logged on
/// it, so the app never has to ask.
///
/// Pure: no database, no Supabase, no clock. Everything here is a function of
/// its arguments, which is what makes it testable without mocking.

/// The steps real stacks and plate sets actually use, coarsest first.
///
/// An inferred step is snapped to one of these rather than reported raw: a raw
/// divisor like 15 is arithmetically valid but isn't a thing any machine does,
/// and offering it as a fact would be worse than offering nothing.
const _standardIncrements = <double>[10, 5, 2.5, 2, 1.25, 1, 0.5];

/// Below this many distinct weights there isn't enough evidence to guess.
///
/// One weight tells you nothing — 60 kg is a multiple of 10, of 5, of 2.5 and of
/// 1, and picking among those would be invention rather than inference.
const _minDistinctWeights = 2;

/// The step [weights] suggests this machine moves in, or null if they don't say.
///
/// Works off the greatest common divisor of the distinct weights. The reasoning
/// that makes this safe rather than merely plausible: the machine's true step
/// divides every weight you have ever successfully loaded, so it divides their
/// GCD too. Anything the GCD divides is therefore also a multiple of the true
/// step — which means a suggestion built on this number is always physically
/// achievable, even when the number is coarser than the machine can really do.
///
/// The failure mode is one-sided on purpose. Guessing too coarse means
/// suggesting +5 kg where +2.5 was available: mildly annoying, and you can
/// correct it. Guessing too fine means suggesting 42.5 kg on a stack that only
/// does 5s: an impossible instruction, which costs more trust than saying
/// nothing at all. This can only ever err the first way.
///
/// Returns null when the evidence is too thin, rather than a default — the
/// caller distinguishes "not known" from "known to be 2.5", and only a
/// confirmed value is ever written back to the machine.
double? inferIncrement(Iterable<double?> weights) {
  // Zero and null are bodyweight or unlogged, not evidence about a stack.
  final distinct = weights
      .whereType<double>()
      .where((w) => w > 0)
      .map(_toHundredths)
      .toSet();

  if (distinct.length < _minDistinctWeights) return null;

  final divisor = distinct.reduce(_gcd);

  // Largest standard step that divides the GCD exactly. Because it divides the
  // GCD, and the GCD divides every logged weight, it divides every logged
  // weight too — so the safety argument above survives the snapping.
  for (final candidate in _standardIncrements) {
    final c = _toHundredths(candidate);
    if (divisor % c == 0) return candidate;
  }

  return null;
}

/// The lightest weight ever logged here — the bottom of the stack, as far as
/// the evidence goes.
///
/// An estimate that can only be too high: you may simply never have pinned the
/// lightest plate. Used to stop a suggestion dropping below what the machine
/// can physically do, so being conservative is the right direction.
double? inferMinWeight(Iterable<double?> weights) {
  final real = weights.whereType<double>().where((w) => w > 0);
  if (real.isEmpty) return null;
  return real.reduce((a, b) => a < b ? a : b);
}

/// Whether [weights] look like they came from more than one machine.
///
/// A single stack produces weights that are all multiples of one step. A blend
/// of a 2.5 kg stack and a 5 kg stack does not — and [inferIncrement] would
/// resolve that blend to 2.5, which is unachievable on the coarser machine.
///
/// This is the signal behind offering to split an exercise's history across two
/// machines. It deliberately only fires when the finer readings are a minority:
/// a stack that genuinely does 2.5s produces odd multiples routinely, not
/// occasionally.
bool looksLikeTwoMachines(Iterable<double?> weights) {
  final distinct = weights
      .whereType<double>()
      .where((w) => w > 0)
      .map(_toHundredths)
      .toSet();

  if (distinct.length < 4) return false;

  final coarse = _toHundredths(5);
  final onCoarse = distinct.where((w) => w % coarse == 0).length;
  final offCoarse = distinct.length - onCoarse;

  // Most readings sit on the coarse grid, a few don't: consistent with mostly
  // using the 5 kg machine and occasionally the finer one.
  return offCoarse > 0 && offCoarse * 3 <= onCoarse;
}

/// Weights carry at most two decimals (1.25 is the finest step anyone uses), so
/// hundredths of a kg as an integer is exact where doubles are not.
///
/// Without this, `42.5 % 2.5` can land on 2.4999999999999996 and the divisor
/// check silently fails.
int _toHundredths(double kg) => (kg * 100).round();

int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final t = y;
    y = x % y;
    x = t;
  }
  return x;
}
