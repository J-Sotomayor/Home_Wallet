import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/expense_split.dart';

void main() {
  test('splits a bill proportionally and preserves every cent', () {
    final shares = calculateProportionalShares(
      totalMinor: 11000,
      weights: const {'person-a': 100000, 'person-b': 120000},
    );

    expect(shares, const {'person-a': 5000, 'person-b': 6000});
    expect(shares.values.reduce((a, b) => a + b), 11000);
  });

  test('rejects missing or invalid income weights', () {
    expect(
      calculateProportionalShares(
        totalMinor: 1000,
        weights: const {'person-a': 0, 'person-b': 0},
      ),
      isEmpty,
    );
    expect(
      calculateProportionalShares(
        totalMinor: 1000,
        weights: const {'person-a': 1000, 'person-b': -1},
      ),
      isEmpty,
    );
  });
}
