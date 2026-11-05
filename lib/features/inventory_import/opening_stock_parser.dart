import '../products/import/import_planner.dart';

/// Import qatorini o'qishda yuz bergan xato.
class OpeningStockParseException implements Exception {
  final String message;

  const OpeningStockParseException(this.message);

  @override
  String toString() => message;
}

/// Excel'dagi bitta qoldiq qatori.
class OpeningStockRow {
  final int row;
  final String sku;
  final String? name;
  final String? category;
  final String? containerType;
  final num? unitCount;
  final num? unitWeightKg;
  final String? lotNumber;
  final String? expiryDate;
  final String? locationCode;
  final num? shelfLifeMonths;

  const OpeningStockRow({
    required this.row,
    required this.sku,
    this.name,
    this.category,
    this.containerType,
    this.unitCount,
    this.unitWeightKg,
    this.lotNumber,
    this.expiryDate,
    this.locationCode,
    this.shelfLifeMonths,
  });

  Map<String, dynamic> toJson() {
    return {
      'row': row,
      'sku': sku,
      'name': name,
      'category': category,
      'container_type': containerType,
      'unit_count': unitCount,
      'unit_weight_kg': unitWeightKg,
      'lot_number': lotNumber,
      'expiry_date': expiryDate,
      'location_code': locationCode,
      'shelf_life_months': shelfLifeMonths,
    };
  }
}

class OpeningStockParseResult {
  final String sheetName;
  final List<OpeningStockRow> rows;

  const OpeningStockParseResult({required this.sheetName, required this.rows});
}

const Map<String, List<String>> _aliases = {
  'sku': ['kod', 'kod (sku)', 'sku', 'code', '\u043a\u043e\u0434'],
  'name': [
    'nomi',
    'nom',
    'name',
    '\u043d\u0430\u0437\u0432\u0430\u043d\u0438\u0435',
    '\u043d\u0430\u0438\u043c\u0435\u043d\u043e\u0432\u0430\u043d\u0438\u0435',
  ],
  'category': [
    'kategoriya',
    'category',
    '\u043a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u044f',
  ],
  'container_type': [
    'idish turi',
    'idish',
    'container',
    '\u0442\u0430\u0440\u0430',
  ],
  'unit_count': [
    'idish soni',
    'soni',
    'count',
    '\u0441\u043e\u043d\u0438',
    '\u043a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e',
  ],
  'unit_weight_kg': [
    '1 idish, kg',
    '1 idish kg',
    '1 idish',
    'kg',
    "og'irlik",
    'weight',
    '\u0432\u0435\u0441',
  ],
  'lot_number': ['lot raqami', 'lot', 'partiya'],
  'expiry_date': [
    'yaroqlilik muddati',
    'muddati',
    'expiry',
    '\u0441\u0440\u043e\u043a \u0433\u043e\u0434\u043d\u043e\u0441\u0442\u0438',
  ],
  'location_code': ['joylashuv kodi', 'joylashuv', 'location'],
  'shelf_life_months': ['yaroqlilik (oy)', 'muddat (oy)', 'shelf life'],
};

String _normalizeHeader(String value) {
  var text = value.trim().toLowerCase();
  text = text.replaceAll('\u00a0', ' ');
  text = text.replaceAll('\u2019', "'");
  text = text.replaceAll('\u2018', "'");
  text = text.replaceAll('\u02bb', "'");
  text = text.replaceAll('\u02bc', "'");
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text;
}

/// Excel faylidan 'Qoldiq' varaqini (bo'lmasa birinchi varaqni) o'qiydi.
OpeningStockParseResult parseOpeningStockSheet(List<int> xlsxBytes) {
  final names = sheetNames(xlsxBytes);
  if (names.isEmpty) {
    throw const OpeningStockParseException('Faylda varaq topilmadi');
  }
  final sheetName = names.contains('Qoldiq') ? 'Qoldiq' : names.first;
  return parseOpeningStockRows(parseSheet(xlsxBytes, sheetName));
}

/// Tayyor [ParsedSheet] dan qatorlarni ajratadi.
OpeningStockParseResult parseOpeningStockRows(ParsedSheet sheet) {
  if (sheet.rows.isEmpty) {
    throw const OpeningStockParseException(
      "Majburiy ustunlar topilmadi: kod (SKU), idish soni",
    );
  }

  final header = sheet.rows.first;
  final columns = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final normalized = _normalizeHeader(header[i]);
    if (normalized.isEmpty) continue;
    for (final entry in _aliases.entries) {
      if (columns.containsKey(entry.key)) continue;
      if (entry.value.contains(normalized)) {
        columns[entry.key] = i;
        break;
      }
    }
  }

  final missing = <String>[];
  if (!columns.containsKey('sku')) missing.add('kod (SKU)');
  if (!columns.containsKey('unit_count')) missing.add('idish soni');
  if (missing.isNotEmpty) {
    throw OpeningStockParseException(
      'Majburiy ustunlar topilmadi: ${missing.join(', ')}',
    );
  }

  final rows = <OpeningStockRow>[];
  for (var i = 1; i < sheet.rows.length; i++) {
    final raw = sheet.rows[i];
    if (raw.every((cell) => cell.trim().isEmpty)) continue;

    final rowNumber = i + 1;
    final sku = _cell(raw, columns['sku']) ?? '';

    final unitCount = _parseNumber(
      _cell(raw, columns['unit_count']),
      rowNumber,
      'idish soni',
    );
    final unitWeight = _parseNumber(
      _cell(raw, columns['unit_weight_kg']),
      rowNumber,
      '1 idish og\'irligi',
    );
    final shelfLife = _parseNumber(
      _cell(raw, columns['shelf_life_months']),
      rowNumber,
      'yaroqlilik (oy)',
    );

    rows.add(
      OpeningStockRow(
        row: rowNumber,
        sku: sku,
        name: _cell(raw, columns['name']),
        category: _cell(raw, columns['category']),
        containerType: _cell(raw, columns['container_type']),
        unitCount: unitCount,
        unitWeightKg: unitWeight,
        lotNumber: _cell(raw, columns['lot_number']),
        expiryDate: _normalizeDate(_cell(raw, columns['expiry_date'])),
        locationCode: _cell(raw, columns['location_code']),
        shelfLifeMonths: shelfLife,
      ),
    );
  }

  return OpeningStockParseResult(sheetName: sheet.name, rows: rows);
}

String? _cell(List<String> row, int? index) {
  if (index == null || index < 0 || index >= row.length) return null;
  final text = row[index].trim();
  return text.isEmpty ? null : text;
}

num? _parseNumber(String? value, int row, String column) {
  if (value == null) return null;
  final cleaned = value
      .replaceAll('\u00a0', ' ')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  final parsed = num.tryParse(cleaned);
  if (parsed == null) {
    throw OpeningStockParseException('$row-qator: "$column" son emas: $value');
  }
  return parsed;
}

String? _normalizeDate(String? value) {
  if (value == null) return null;
  final text = value.trim();
  if (text.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (iso != null) {
    final candidate = '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}';
    return _isValidIsoDate(candidate) ? candidate : text;
  }

  final dotted = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(text);
  if (dotted != null) {
    final day = dotted.group(1)!.padLeft(2, '0');
    final month = dotted.group(2)!.padLeft(2, '0');
    final year = dotted.group(3)!;
    final candidate = '$year-$month-$day';
    return _isValidIsoDate(candidate) ? candidate : text;
  }

  final serial = double.tryParse(text);
  if (serial != null && serial >= 20000 && serial <= 80000) {
    final date = DateTime(1899, 12, 30).add(Duration(days: serial.round()));
    return _formatDate(date);
  }

  return text;
}

bool _isValidIsoDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed != null && _formatDate(parsed) == value;
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
