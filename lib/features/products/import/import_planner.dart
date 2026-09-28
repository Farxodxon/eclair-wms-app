import 'package:excel/excel.dart';

/// Sabab matnlari (o'zbekcha, foydalanuvchiga ko'rsatiladi).
class SkipReasons {
  static const String noName = "Nomi yo'q";
  static const String noSku = "SKU yo'q";
  static const String duplicateSku = "Faylda takrorlangan SKU";
  static const String existsInDb = "Bazada allaqachon bor";
}

/// Bitta Excel varaqining to'liq matnli ko'rinishi.
///
/// [rows] - har bir qator `List<String>` (har bir hujayra matnga aylantirilgan,
/// bo'sh yoki `null` hujayra - `''`).
/// [columnCount] - faylda mavjud eng keng ustunlar soni.
class ParsedSheet {
  final String name;
  final List<List<String>> rows;
  final int columnCount;

  const ParsedSheet({
    required this.name,
    required this.rows,
    required this.columnCount,
  });

  /// 0-dan boshlanuvchi ustun indeksi uchun Excel harfi (0 -> A, 1 -> B, ...).
  static String columnLetter(int index) {
    var value = index;
    final buffer = StringBuffer();
    while (value >= 0) {
      buffer.write(String.fromCharCode(65 + (value % 26)));
      value = (value ~/ 26) - 1;
    }
    return buffer.toString().split('').reversed.join();
  }
}

/// Excel faylidagi barcha varaqlar nomlari.
List<String> sheetNames(List<int> xlsxBytes) {
  final excel = Excel.decodeBytes(xlsxBytes);
  return excel.sheets.keys.toList();
}

/// [xlsxBytes] ichidagi [sheetName] varaqini o'qib, har bir hujayrani
/// xavfsiz matn ko'rinishiga o'tkazadi.
ParsedSheet parseSheet(List<int> xlsxBytes, String sheetName) {
  final excel = Excel.decodeBytes(xlsxBytes);
  final sheet = excel[sheetName];
  final rawRows = sheet.rows;

  var columnCount = 0;
  final rows = <List<String>>[];
  for (final rawRow in rawRows) {
    final converted = <String>[];
    for (final cell in rawRow) {
      converted.add(_cellToString(cell));
    }
    if (converted.length > columnCount) columnCount = converted.length;
    rows.add(converted);
  }

  return ParsedSheet(
    name: sheetName,
    rows: rows,
    columnCount: columnCount,
  );
}

String _cellToString(Data? cell) {
  if (cell == null) return '';
  final value = cell.value;
  if (value == null) return '';
  return cellValueToString(value);
}

/// excel paketining turli hujayra turlarini matnga o'tkazadi.
String cellValueToString(CellValue value) {
  return switch (value) {
    TextCellValue(:final value) => value.toString(),
    IntCellValue(:final value) => value.toString(),
    DoubleCellValue(:final value) => _doubleToString(value),
    BoolCellValue(:final value) => value.toString(),
    DateCellValue() => value.toString(),
    DateTimeCellValue() => value.toString(),
    TimeCellValue() => value.toString(),
    FormulaCellValue(:final formula) => formula,
  };
}

String _doubleToString(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Ustunlarni qanday o'qash kerakligi (foydalanuvchi UI'da sozlaydi).
class ImportMapping {
  final bool hasHeaderRow;
  final int? skuColumn;
  final int nameColumn;
  final int? shelfLifeColumn;
  final bool shelfLifeInMonths;
  final Map<String, int> attributeColumns;
  final String defaultUnit;
  final String skuPrefix;
  final int? serialColumn;

  const ImportMapping({
    this.hasHeaderRow = true,
    this.skuColumn,
    required this.nameColumn,
    this.shelfLifeColumn,
    this.shelfLifeInMonths = false,
    this.attributeColumns = const {},
    this.defaultUnit = 'kg',
    this.skuPrefix = 'PLK-',
    this.serialColumn,
  });

  ImportMapping copyWith({
    bool? hasHeaderRow,
    int? skuColumn,
    int? nameColumn,
    int? shelfLifeColumn,
    bool? shelfLifeInMonths,
    Map<String, int>? attributeColumns,
    String? defaultUnit,
    String? skuPrefix,
    int? serialColumn,
  }) {
    return ImportMapping(
      hasHeaderRow: hasHeaderRow ?? this.hasHeaderRow,
      skuColumn: skuColumn ?? this.skuColumn,
      nameColumn: nameColumn ?? this.nameColumn,
      shelfLifeColumn: shelfLifeColumn ?? this.shelfLifeColumn,
      shelfLifeInMonths: shelfLifeInMonths ?? this.shelfLifeInMonths,
      attributeColumns: attributeColumns ?? this.attributeColumns,
      defaultUnit: defaultUnit ?? this.defaultUnit,
      skuPrefix: skuPrefix ?? this.skuPrefix,
      serialColumn: serialColumn ?? this.serialColumn,
    );
  }
}

/// Yaratiladigan bitta mahsulot (tayyor `POST /products` body).
class PlannedProduct {
  final int rowNumber;
  final String sku;
  final String name;
  final String unit;
  final int? defaultShelfLifeDays;
  final Map<String, dynamic> attributes;

  const PlannedProduct({
    required this.rowNumber,
    required this.sku,
    required this.name,
    required this.unit,
    this.defaultShelfLifeDays,
    this.attributes = const {},
  });

  /// `category_id` bu yerda qo'shilmaydi - u import ekranida tanlanadi.
  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{
      'sku': sku,
      'name': name,
      'unit': unit,
      'attributes': Map<String, dynamic>.from(attributes),
    };
    if (defaultShelfLifeDays != null) {
      body['default_shelf_life_days'] = defaultShelfLifeDays;
    }
    return body;
  }
}

/// O'tkazilgan (yaratilmagan) qator.
class SkippedRow {
  final int rowNumber;
  final String sku;
  final String name;
  final String reason;

  const SkippedRow({
    required this.rowNumber,
    required this.sku,
    required this.name,
    required this.reason,
  });
}

class ImportPlan {
  final List<PlannedProduct> toCreate;
  final List<SkippedRow> skipped;

  const ImportPlan({required this.toCreate, required this.skipped});

  /// Sabablar bo'yicha guruhlangan sonlar.
  Map<String, int> get skippedByReason {
    final grouped = <String, int>{};
    for (final row in skipped) {
      grouped[row.reason] = (grouped[row.reason] ?? 0) + 1;
    }
    return grouped;
  }
}

ImportPlan buildPlan(ParsedSheet sheet, ImportMapping mapping) {
  final toCreate = <PlannedProduct>[];
  final skipped = <SkippedRow>[];
  final seenSkus = <String>{};

  final firstDataIndex = mapping.hasHeaderRow ? 1 : 0;

  for (var i = firstDataIndex; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    // [i] - 0-dan boshlanuvchi qator indeksi; foydalanuvchiga 1-dan
    // ko'rsatamiz (sarlavha qatori ham hisobga olinadi).
    final rowNumber = i + 1;

    final name = _valueAt(row, mapping.nameColumn);
    final skuFromColumn =
        mapping.skuColumn != null ? _valueAt(row, mapping.skuColumn!) : '';

    if (name.isEmpty) {
      skipped.add(SkippedRow(
        rowNumber: rowNumber,
        sku: skuFromColumn,
        name: name,
        reason: SkipReasons.noName,
      ));
      continue;
    }

    String sku;
    if (mapping.skuColumn != null) {
      if (skuFromColumn.isEmpty) {
        skipped.add(SkippedRow(
          rowNumber: rowNumber,
          sku: skuFromColumn,
          name: name,
          reason: SkipReasons.noSku,
        ));
        continue;
      }
      sku = skuFromColumn;
    } else {
      final serial = mapping.serialColumn != null
          ? _valueAt(row, mapping.serialColumn!)
          : rowNumber.toString();
      if (serial.isEmpty) {
        skipped.add(SkippedRow(
          rowNumber: rowNumber,
          sku: '',
          name: name,
          reason: SkipReasons.noSku,
        ));
        continue;
      }
      sku = '${mapping.skuPrefix}$serial';
    }

    if (!seenSkus.add(sku)) {
      skipped.add(SkippedRow(
        rowNumber: rowNumber,
        sku: sku,
        name: name,
        reason: SkipReasons.duplicateSku,
      ));
      continue;
    }

    final attributes = <String, dynamic>{};
    for (final entry in mapping.attributeColumns.entries) {
      final value = _valueAt(row, entry.value);
      if (value.isNotEmpty) attributes[entry.key] = value;
    }

    toCreate.add(PlannedProduct(
      rowNumber: rowNumber,
      sku: sku,
      name: name,
      unit: mapping.defaultUnit,
      defaultShelfLifeDays: _shelfLifeDays(row, mapping),
      attributes: attributes,
    ));
  }

  return ImportPlan(toCreate: toCreate, skipped: skipped);
}

String _valueAt(List<String> row, int columnIndex) {
  if (columnIndex < 0 || columnIndex >= row.length) return '';
  return row[columnIndex].trim();
}

int? _shelfLifeDays(List<String> row, ImportMapping mapping) {
  final column = mapping.shelfLifeColumn;
  if (column == null) return null;
  final raw = _valueAt(row, column);
  if (raw.isEmpty) return null;
  final parsed = num.tryParse(raw);
  if (parsed == null) return null;
  if (mapping.shelfLifeInMonths) return (parsed * 30).round();
  return parsed.round();
}
