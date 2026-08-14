Map<String, int> calculateProportionalShares({
  required int totalMinor,
  required Map<String, int> weights,
}) {
  if (totalMinor <= 0 ||
      weights.length < 2 ||
      weights.values.any((value) => value < 0)) {
    return const {};
  }
  final weightTotal = weights.values.fold<int>(0, (sum, value) => sum + value);
  if (weightTotal <= 0) return const {};

  final ids = weights.keys.toList()..sort();
  var remaining = totalMinor;
  final shares = <String, int>{};
  for (var index = 0; index < ids.length; index++) {
    final id = ids[index];
    final share =
        index == ids.length - 1
            ? remaining
            : (totalMinor * weights[id]! / weightTotal).round();
    shares[id] = share;
    remaining -= share;
  }
  return shares;
}
