/// Player-facing gem amounts.
///
/// The table still stores integer units (the old cent-sized numbers).
/// Never render a cent sign or a "play coins" label from here.
String gemCount(int amount) {
  final n = amount.abs();
  final unit = n == 1 ? 'gem' : 'gems';
  return amount < 0 ? '-$n $unit' : '$n $unit';
}

/// Signed change, always with a plus when the player gained gems.
String gemDelta(int amount) {
  if (amount > 0) return '+${gemCount(amount)}';
  return gemCount(amount);
}
