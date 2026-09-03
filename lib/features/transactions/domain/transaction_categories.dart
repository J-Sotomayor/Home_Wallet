import 'finance_models.dart';

abstract final class TransactionCategories {
  static const expenses = <String>[
    'Alimentación',
    'Arriendo',
    'Luz',
    'Agua',
    'Internet',
    'Gas',
    'Vivienda',
    'Servicios básicos',
    'Transporte',
    'Salud',
    'Educación',
    'Entretenimiento',
    'Ropa y accesorios',
    'Compras',
    'Deudas',
    'Otro',
  ];

  static const incomes = <String>[
    'Sueldo',
    'Negocio',
    'Honorarios',
    'Ventas',
    'Bonos',
    'Intereses',
    'Reembolsos',
    'Préstamos recibidos',
    'Otro',
  ];

  static const savings = <String>[
    'Fondo de emergencia',
    'Vacaciones',
    'Inversión',
    'Vivienda futura',
    'Meta personal',
    'Otro',
  ];

  static const _expenseKeywords = <String, List<String>>{
    'Alimentación': [
      'alimentacion',
      'hamburguesa',
      'pizza',
      'comida',
      'almuerzo',
      'desayuno',
      'merienda',
      'cena',
      'supermercado',
      'restaurante',
      'cafeteria',
      'mercado',
      'panaderia',
      'pollo',
      'carne',
      'frutas',
      'verduras',
    ],
    'Arriendo': ['arriendo', 'alquiler', 'renta de casa', 'renta departamento'],
    'Luz': [
      'luz',
      'electricidad',
      'energia electrica',
      'planilla electrica',
      'empresa electrica',
      'eee quito',
    ],
    'Agua': ['agua potable', 'planilla de agua', 'servicio de agua'],
    'Internet': ['internet', 'wifi', 'netlife', 'fibra optica', 'paquete cnt'],
    'Gas': ['gas', 'glp', 'bombona', 'cilindro de gas'],
    'Vivienda': [
      'vivienda',
      'ferreteria',
      'reparacion de casa',
      'muebles',
      'electrodomestico',
      'condominio',
      'alicuota',
    ],
    'Servicios básicos': [
      'telefono',
      'celular',
      'plan movil',
      'servicio basico',
    ],
    'Transporte': [
      'transporte',
      'taxi',
      'uber',
      'cabify',
      'bus',
      'metro',
      'pasaje',
      'gasolina',
      'combustible',
      'parqueadero',
      'peaje',
    ],
    'Salud': [
      'salud',
      'farmacia',
      'medicina',
      'medico',
      'doctor',
      'hospital',
      'clinica',
      'consulta medica',
      'laboratorio',
      'dentista',
    ],
    'Educación': [
      'educacion',
      'estudio',
      'colegio',
      'escuela',
      'universidad',
      'matricula',
      'curso',
      'libro',
      'cuaderno',
      'utiles escolares',
      'capacitacion',
    ],
    'Entretenimiento': [
      'entretenimiento',
      'cine',
      'netflix',
      'spotify',
      'streaming',
      'videojuego',
      'juego',
      'concierto',
      'discoteca',
      'paseo',
    ],
    'Ropa y accesorios': [
      'ropa',
      'camisa',
      'pantalon',
      'zapato',
      'vestido',
      'chaqueta',
      'accesorio',
    ],
    'Deudas': [
      'deuda',
      'prestamo',
      'credito',
      'cuota tarjeta',
      'pago de tarjeta',
    ],
    'Compras': ['compra', 'tienda', 'regalo', 'articulo', 'producto'],
  };

  static const _incomeKeywords = <String, List<String>>{
    'Sueldo': ['sueldo', 'salario', 'nomina', 'quincena'],
    'Negocio': ['negocio', 'emprendimiento', 'ganancia del negocio'],
    'Honorarios': [
      'honorario',
      'servicio profesional',
      'trabajo freelance',
      'freelance',
    ],
    'Ventas': ['venta', 'vendido'],
    'Bonos': ['bono', 'comision', 'utilidades'],
    'Intereses': ['interes', 'rendimiento'],
    'Reembolsos': ['reembolso', 'devolucion'],
    'Préstamos recibidos': [
      'prestamo recibido',
      'dinero prestado',
      'me prestaron',
    ],
  };

  static const _savingKeywords = <String, List<String>>{
    'Fondo de emergencia': ['emergencia', 'imprevisto', 'fondo de emergencia'],
    'Vacaciones': ['vacacion', 'viaje', 'turismo'],
    'Inversión': ['inversion', 'invertir', 'acciones', 'deposito a plazo'],
    'Vivienda futura': ['casa propia', 'vivienda futura', 'entrada de casa'],
    'Meta personal': ['meta personal', 'objetivo personal'],
  };

  static const _ignoredLearningTokens = <String>{
    'comprar',
    'compra',
    'pagar',
    'pago',
    'gasto',
    'ingreso',
    'ahorro',
    'para',
    'por',
    'con',
    'sin',
    'del',
    'las',
    'los',
    'una',
    'uno',
    'unos',
    'unas',
    'que',
    'este',
    'esta',
    'hoy',
    'ayer',
  };

  static List<String> forType(TransactionType type) => switch (type) {
    TransactionType.expense => expenses,
    TransactionType.income => incomes,
    TransactionType.saving => savings,
  };

  static List<String> get all =>
      {...expenses, ...incomes, ...savings}.toList()..sort();

  static String defaultFor(TransactionType type) => forType(type).first;

  static String normalizedFor(TransactionType type, String category) {
    final values = forType(type);
    return values.contains(category) ? category : values.last;
  }

  static String normalizeExisting(
    TransactionType type,
    String category,
    String description,
  ) {
    final values = forType(type);
    final cleanCategory = category.trim();
    const legacyOther = {'Otros gastos', 'Otros ingresos', 'Otros ahorros'};
    if (legacyOther.contains(cleanCategory) || cleanCategory.isEmpty) {
      return suggestFor(type, description);
    }
    if (values.contains(cleanCategory) && cleanCategory != 'Otro') {
      return cleanCategory;
    }
    // Categories created by the household are valid even though they are not
    // part of the built-in catalog. Previously they were rewritten as “Otro”
    // every time the encrypted transaction was read.
    if (cleanCategory != 'Otro') return cleanCategory;
    return suggestFor(type, description);
  }

  /// Suggests a category while the user types a transaction description.
  ///
  /// Custom categories participate in two ways: their name is matched against
  /// the description and previous manual classifications are reused as local
  /// examples. The transaction history is already available in the encrypted
  /// household stream, so this does not send descriptions to an external
  /// service.
  static String suggestFor(
    TransactionType type,
    String description, {
    Iterable<String> customCategories = const [],
    Iterable<FinanceTransaction> previousTransactions = const [],
  }) {
    final text = _normalize(description);
    if (text.isEmpty) return 'Otro';

    final availableCategories = <String>{
      ...forType(type),
      ...customCategories.map((category) => category.trim()),
    };
    final learned = _suggestFromHistory(
      type: type,
      description: text,
      availableCategories: availableCategories,
      previousTransactions: previousTransactions,
    );
    if (learned != null) return learned;

    final custom = _suggestCustomCategory(text, customCategories);
    if (custom != null) return custom;

    final keywordCatalog = switch (type) {
      TransactionType.expense => _expenseKeywords,
      TransactionType.income => _incomeKeywords,
      TransactionType.saving => _savingKeywords,
    };
    for (final entry in keywordCatalog.entries) {
      if (entry.value.any((keyword) => _containsPhrase(text, keyword))) {
        return entry.key;
      }
    }
    return 'Otro';
  }

  static String? _suggestCustomCategory(
    String description,
    Iterable<String> customCategories,
  ) {
    final descriptionTokens = _tokenize(description).map(_stem).toSet();
    for (final category in customCategories) {
      final cleanCategory = category.trim();
      if (cleanCategory.isEmpty) continue;
      final normalizedCategory = _normalize(cleanCategory);
      if (_containsPhrase(description, normalizedCategory)) {
        return cleanCategory;
      }
      final categoryTokens =
          _tokenize(
            normalizedCategory,
          ).where((token) => token.length >= 4).map(_stem).toSet();
      if (categoryTokens.isNotEmpty &&
          categoryTokens.every(descriptionTokens.contains)) {
        return cleanCategory;
      }
    }
    return null;
  }

  static String? _suggestFromHistory({
    required TransactionType type,
    required String description,
    required Set<String> availableCategories,
    required Iterable<FinanceTransaction> previousTransactions,
  }) {
    final currentTokens = _learningTokens(description);
    String? bestCategory;
    var bestScore = 0;

    for (final transaction in previousTransactions) {
      if (transaction.type != type ||
          transaction.category == 'Otro' ||
          !availableCategories.contains(transaction.category)) {
        continue;
      }
      final previousDescription = _normalize(transaction.description);
      if (previousDescription == description) return transaction.category;

      final common = currentTokens.intersection(
        _learningTokens(previousDescription),
      );
      if (common.isEmpty) continue;
      final hasDistinctiveToken = common.any((token) => token.length >= 6);
      if (common.length < 2 && !hasDistinctiveToken) continue;

      final score =
          common.length * 10 +
          common.fold<int>(0, (total, token) => total + token.length);
      if (score > bestScore) {
        bestScore = score;
        bestCategory = transaction.category;
      }
    }
    return bestCategory;
  }

  static Set<String> _learningTokens(String value) =>
      _tokenize(value)
          .map(_stem)
          .where(
            (token) =>
                token.length >= 3 && !_ignoredLearningTokens.contains(token),
          )
          .toSet();

  static Iterable<String> _tokenize(String value) =>
      _normalize(value).split(' ').where((token) => token.isNotEmpty);

  static String _stem(String value) {
    if (value.length > 5 && value.endsWith('es')) {
      return value.substring(0, value.length - 2);
    }
    if (value.length > 4 && value.endsWith('s')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _containsPhrase(String value, String phrase) {
    final normalizedPhrase = _normalize(phrase);
    if (!normalizedPhrase.contains(' ')) {
      final expected = _stem(normalizedPhrase);
      return _tokenize(value).map(_stem).contains(expected);
    }
    return ' $value '.contains(' $normalizedPhrase ');
  }
}
