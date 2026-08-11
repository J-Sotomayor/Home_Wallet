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
    const legacyOther = {'Otros gastos', 'Otros ingresos', 'Otros ahorros'};
    if (legacyOther.contains(category)) return suggestFor(type, description);
    if (values.contains(category) && category != 'Otro') return category;
    return suggestFor(type, description);
  }

  static String suggestFor(TransactionType type, String description) {
    final text = _normalize(description);
    if (type == TransactionType.income) {
      if (text.contains('sueldo') ||
          text.contains('salario') ||
          text.contains('nómina')) {
        return 'Sueldo';
      }
      if (text.contains('venta')) return 'Ventas';
      if (_containsAny(text, const [
        'prestaron',
        'prestamo recibido',
        'préstamo recibido',
      ])) {
        return 'Préstamos recibidos';
      }
      if (text.contains('reembolso') || text.contains('devolucion')) {
        return 'Reembolsos';
      }
    }
    if (type == TransactionType.expense) {
      if (_containsAny(text, const [
        'comida',
        'supermercado',
        'restaurante',
        'mercado',
      ])) {
        return 'Alimentación';
      }
      if (text.contains('arriendo') || text.contains('alquiler')) {
        return 'Arriendo';
      }
      if (_containsAny(text, const [
        'eee quito',
        'empresa electrica',
        'energia electrica',
        'planilla de luz',
      ])) {
        return 'Luz';
      }
      if (_containsAny(text, const ['agua potable', 'planilla de agua'])) {
        return 'Agua';
      }
      if (_containsAny(text, const ['internet', 'paquetes cnt', 'netlife'])) {
        return 'Internet';
      }
      if (_containsAny(text, const ['gas', 'glp'])) {
        return 'Gas';
      }
      if (_containsAny(text, const [
        'ropa',
        'camisa',
        'pantalon',
        'pantalón',
        'zapato',
        'vestido',
      ])) {
        return 'Ropa y accesorios';
      }
      if (_containsAny(text, const ['farmacia', 'medico', 'hospital'])) {
        return 'Salud';
      }
    }
    if (type == TransactionType.saving &&
        (text.contains('vacacion') || text.contains('viaje'))) {
      return 'Vacaciones';
    }
    return 'Otro';
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u');

  static bool _containsAny(String value, List<String> words) =>
      words.any(value.contains);
}
