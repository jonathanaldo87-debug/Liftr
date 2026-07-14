import 'dart:math';

/// Auto-generated names for guest accounts.
///
/// A guest never types anything, so the app has to invent a name it can show in
/// the header and on Profile. Two words plus a number: readable, gym-flavoured,
/// and collision-resistant enough that two guests on the same device history
/// won't look identical. Nothing depends on it being unique — the account is
/// keyed by its auth id, not this string.
String generateUsername([Random? random]) {
  final rng = random ?? Random();
  final adjective = _adjectives[rng.nextInt(_adjectives.length)];
  final noun = _nouns[rng.nextInt(_nouns.length)];
  final number = rng.nextInt(9000) + 1000; // always 4 digits

  return '$adjective $noun $number';
}

/// Initials for the avatar circle: "Swift Falcon 4821" -> "SF".
String initialsFromUsername(String username) {
  final words = username
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-z]').hasMatch(w))
      .toList();

  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

const _adjectives = [
  'Swift', 'Iron', 'Steel', 'Bold', 'Silent', 'Rapid', 'Solid', 'Fierce',
  'Steady', 'Brave', 'Sharp', 'Mighty', 'Quiet', 'Rugged', 'Stout', 'Nimble',
];

const _nouns = [
  'Falcon', 'Bison', 'Otter', 'Badger', 'Heron', 'Lynx', 'Bear', 'Ram',
  'Wolf', 'Stag', 'Crane', 'Boar', 'Hawk', 'Ox', 'Panther', 'Ibex',
];
