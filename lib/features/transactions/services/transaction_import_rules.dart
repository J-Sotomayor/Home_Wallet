import '../domain/finance_models.dart';
import '../domain/transaction_categories.dart';

abstract final class TransactionImportRules {
  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');

  static int? parseSignedMinor(String input) {
    if (input.trim().isEmpty) return null;
    final negative =
        input.contains('-') || (input.contains('(') && input.contains(')'));
    var value = input.replaceAll(RegExp(r'[^0-9,.]'), '');
    if (value.isEmpty) return null;
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');
    final separator = comma > dot ? comma : dot;
    String whole;
    String decimals;
    if (separator >= 0 && value.length - separator - 1 <= 2) {
      whole = value.substring(0, separator).replaceAll(RegExp(r'[,\.]'), '');
      decimals = value.substring(separator + 1).padRight(2, '0');
    } else {
      whole = value.replaceAll(RegExp(r'[,\.]'), '');
      decimals = '00';
    }
    final parsedWhole = int.tryParse(whole.isEmpty ? '0' : whole);
    final parsedDecimals = int.tryParse(decimals.isEmpty ? '00' : decimals);
    if (parsedWhole == null || parsedDecimals == null) return null;
    final minor = parsedWhole * 100 + parsedDecimals;
    return negative ? -minor : minor;
  }

  static TransactionType inferType(
    String rawType,
    int signedAmount,
    String description,
  ) {
    final value = normalize('$rawType $description');
    if (_containsAny(value, const ['ahorro', 'saving', 'inversion'])) {
      return TransactionType.saving;
    }
    if (_containsAny(value, const [
      'ingreso',
      'credito',
      'abono',
      'income',
      'deposito',
      'recibida',
    ])) {
      return TransactionType.income;
    }
    if (_containsAny(value, const [
      'gasto',
      'egreso',
      'debito',
      'cargo',
      'expense',
      'enviada',
    ])) {
      return TransactionType.expense;
    }
    return signedAmount < 0 ? TransactionType.expense : TransactionType.income;
  }

  static String categoryFor(
    TransactionType type,
    String description, {
    String sourceCategory = '',
  }) {
    final imported = _matchAllowedCategory(type, sourceCategory);
    if (imported != null) return imported;

    final value = normalize(description);
    if (type == TransactionType.income) {
      if (_containsAny(value, const [
        'sueldo',
        'nomina',
        'salario',
        'rol de pagos',
      ])) {
        return 'Sueldo';
      }
      if (_containsAny(value, const ['honorario'])) return 'Honorarios';
      if (_containsAny(value, const ['bono'])) return 'Bonos';
      if (_containsAny(value, const ['interes', 'rendimiento'])) {
        return 'Intereses';
      }
      if (_containsAny(value, const ['reembolso', 'devolucion'])) {
        return 'Reembolsos';
      }
      if (_containsAny(value, const ['venta'])) return 'Ventas';
      if (_containsAny(value, const ['negocio'])) return 'Negocio';
      if (_containsAny(value, const [
        'prestamo recibido',
        'me prestaron',
        'credito recibido',
      ])) {
        return 'Préstamos recibidos';
      }
      return 'Otro';
    }
    if (type == TransactionType.saving) {
      if (_containsAny(value, const ['vacacion', 'viaje'])) return 'Vacaciones';
      if (_containsAny(value, const ['emergencia'])) {
        return 'Fondo de emergencia';
      }
      if (_containsAny(value, const ['inversion', 'broker'])) {
        return 'Inversión';
      }
      if (_containsAny(value, const ['vivienda', 'casa'])) {
        return 'Vivienda futura';
      }
      if (_containsAny(value, const ['meta'])) return 'Meta personal';
      return 'Otro';
    }
    if (_containsAny(value, const [
      'supermercado',
      'restaurante',
      'comida',
      'mercado',
      'pedidosya',
      'delivery',
    ])) {
      return 'Alimentación';
    }
    if (_containsAny(value, const [
      'arriendo',
      'alquiler',
      'hipoteca',
      'condominio',
    ])) {
      return 'Vivienda';
    }
    if (_containsAny(value, const [
      'luz',
      'agua',
      'internet',
      'telefono',
      'movistar',
      'claro',
      'servicio digital',
      'github',
    ])) {
      return 'Servicios';
    }
    if (_containsAny(value, const [
      'gasolina',
      'estacion de servicio',
      'petro',
      'taxi',
      'uber',
      'bus',
      'metro',
      'peaje',
    ])) {
      return 'Transporte';
    }
    if (_containsAny(value, const [
      'farmacia',
      'medico',
      'clinica',
      'hospital',
    ])) {
      return 'Salud';
    }
    if (_containsAny(value, const [
      'colegio',
      'universidad',
      'curso',
      'libro',
    ])) {
      return 'Educación';
    }
    if (_containsAny(value, const [
      'steam',
      'netflix',
      'spotify',
      'cine',
      'juego',
    ])) {
      return 'Entretenimiento';
    }
    if (_containsAny(value, const [
      'ropa',
      'camisa',
      'pantalon',
      'zapato',
      'vestido',
      'boutique',
    ])) {
      return 'Ropa y accesorios';
    }
    if (_containsAny(value, const [
      'comision',
      'tarifa',
      'iva cobrado',
      'interes mora',
      'prestamo',
      'cuota',
    ])) {
      return 'Deudas';
    }
    if (_containsAny(value, const ['compra', 'consumo pos', 'almacen'])) {
      return 'Compras';
    }
    return 'Otro';
  }

  static DateTime? parseDate(String input) {
    var value = input.trim().toLowerCase();
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    const months = <String, int>{
      'ene': 1,
      'feb': 2,
      'mar': 3,
      'abr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'ago': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dic': 12,
    };
    value = normalize(value).replaceAll('.', '');
    final named = RegExp(
      r'^(\d{1,2})[-/ ]([a-z]{3,})[-/ ](\d{2,4})$',
    ).firstMatch(value);
    if (named != null) {
      final month = months[named.group(2)!.substring(0, 3)];
      final day = int.tryParse(named.group(1)!);
      final rawYear = int.tryParse(named.group(3)!);
      if (day != null && month != null && rawYear != null) {
        return _safeDate(day, month, rawYear < 100 ? 2000 + rawYear : rawYear);
      }
    }

    final parts = value.split(RegExp(r'[/\-.]'));
    if (parts.length != 3) return null;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) return null;
    if (parts[0].length == 4) return _safeDate(third, second, first);
    final year = third < 100 ? 2000 + third : third;
    return _safeDate(first, second, year);
  }

  static String cleanDescription(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 100) return cleaned;
    return cleaned.substring(0, 100).trimRight();
  }

  static DateTime? _safeDate(int day, int month, int year) {
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static String? _matchAllowedCategory(
    TransactionType type,
    String sourceCategory,
  ) {
    final candidate = normalize(sourceCategory);
    if (candidate.isEmpty) return null;
    for (final allowed in TransactionCategories.forType(type)) {
      if (normalize(allowed) == candidate) return allowed;
    }
    const aliases = <String, String>{
      'comida': 'Alimentación',
      'alimentos': 'Alimentación',
      'hogar': 'Vivienda',
      'servicios basicos': 'Servicios',
      'movilidad': 'Transporte',
      'medicina': 'Salud',
      'estudios': 'Educación',
      'ocio': 'Entretenimiento',
      'shopping': 'Compras',
      'prestamos': 'Deudas',
      'salario': 'Sueldo',
      'devoluciones': 'Reembolsos',
      'otros gastos': 'Otro',
      'otros ingresos': 'Otro',
      'otros ahorros': 'Otro',
      'ropa': 'Ropa y accesorios',
    };
    final alias = aliases[candidate];
    return alias != null && TransactionCategories.forType(type).contains(alias)
        ? alias
        : null;
  }

  static bool _containsAny(String value, List<String> words) =>
      words.any(value.contains);
}
