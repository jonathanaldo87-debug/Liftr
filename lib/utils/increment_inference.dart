const _standardIncrements = <double>[10, 5, 2.5, 2, 1.25, 1, 0.5];

const _minDistinctWeights = 2;

double? inferIncrement(Iterable<double?> weights) {
  final distinct = weights
      .whereType<double>()
      .where((w) => w > 0)
      .map(_toHundredths)
      .toSet();

  if (distinct.length < _minDistinctWeights) return null;

  final divisor = distinct.reduce(_gcd);

  for (final candidate in _standardIncrements) {
    final c = _toHundredths(candidate);
    if (divisor % c == 0) return candidate;
  }

  return null;
}

double? inferMinWeight(Iterable<double?> weights) {
  final real = weights.whereType<double>().where((w) => w > 0);
  if (real.isEmpty) return null;
  return real.reduce((a, b) => a < b ? a : b);
}

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
