import 'package:flutter_test/flutter_test.dart';
import 'package:homewallet/features/transactions/domain/finance_models.dart';
import 'package:homewallet/features/transactions/domain/transaction_categories.dart';

void main() {
  group('automatic category suggestions', () {
    test('recognizes common food and education descriptions', () {
      expect(
        TransactionCategories.suggestFor(
          TransactionType.expense,
          'Comprar hamburguesas con papas',
        ),
        'Alimentación',
      );
      expect(
        TransactionCategories.suggestFor(
          TransactionType.expense,
          'Cuadernos para la universidad',
        ),
        'Educación',
      );
    });

    test('matches complete words and does not confuse gasto with gas', () {
      expect(
        TransactionCategories.suggestFor(
          TransactionType.expense,
          'Gasto imprevisto',
        ),
        'Otro',
      );
    });

    test('uses the name of a custom category', () {
      expect(
        TransactionCategories.suggestFor(
          TransactionType.expense,
          'Alimento para mi mascota',
          customCategories: const ['Mascotas'],
        ),
        'Mascotas',
      );
      expect(
        TransactionCategories.suggestFor(
          TransactionType.expense,
          'Compra de alimento para mascotas',
          customCategories: const ['Alimentos mascotas'],
        ),
        'Alimentos mascotas',
      );
    });

    test('learns a custom category from previous manual selections', () {
      final history = [
        FinanceTransaction(
          id: 'previous',
          description: 'Hamburguesa McDonalds',
          category: 'Antojos',
          amountMinor: 750,
          occurredAt: DateTime(2026, 8, 20),
          type: TransactionType.expense,
          createdBy: 'user',
          shared: false,
        ),
      ];

      expect(
        TransactionCategories.suggestFor(
          TransactionType.expense,
          'Combo McDonalds',
          customCategories: const ['Antojos'],
          previousTransactions: history,
        ),
        'Antojos',
      );
    });
  });
}
