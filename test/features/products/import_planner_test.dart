import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wms_app/features/products/import/import_planner.dart';

/// Haqiqiy fayl tizimda yo'q bo'lsa, test o'tkazilmaydi (skipped) - CI/baqa
/// kompilyatorlarda fayl yo'qligi butun test paketini sindirmasin.
const _defaultXlsxName = 'xom_ashyo_royxati va plyonkalar.xlsx';

String _xlsxPath() {
  final override = Platform.environment['WMS_TEST_XLSX'];
  if (override != null && override.isNotEmpty) return override;
  final home = Platform.environment['HOME'] ?? '';
  return '$home/Downloads/$_defaultXlsxName';
}

const _sheetRaw = 'Хом ашё';
const _sheetFilm = 'плёнка';

ImportMapping _rawMapping() => const ImportMapping(
      hasHeaderRow: true,
      skuColumn: 1,
      nameColumn: 2,
      shelfLifeColumn: 4,
      shelfLifeInMonths: true,
      attributeColumns: {
        'usage_purpose': 3,
        'storage_temperature': 5,
      },
      defaultUnit: 'kg',
    );

ImportMapping _filmMapping() => const ImportMapping(
      hasHeaderRow: false,
      nameColumn: 1,
      shelfLifeColumn: 4,
      shelfLifeInMonths: true,
      attributeColumns: {
        'usage_purpose': 2,
        'storage_temperature': 5,
      },
      defaultUnit: 'kg',
      skuPrefix: 'PLK-',
      serialColumn: 0,
    );

void main() {
  final path = _xlsxPath();
  final file = File(path);
  if (!file.existsSync()) {
    test('HAQIQIY FAYL TOPILMADI: $path', () {
      fail(
        'Test uchun haqiqiy Excel fayl kerak: $path\n'
        'WMS_TEST_XLSX o\'zgaruvchisi orqali to\'g\'ri yo\'lni bering.',
      );
    });
    return;
  }

  final bytes = file.readAsBytesSync();

  group('Xom ashyo varaqi (sarlavhali)', () {
    test('sheetNames ikkala varaqni ham qaytaradi', () {
      expect(sheetNames(bytes), [_sheetRaw, _sheetFilm]);
    });

    test('sarlavha qatori skip qilinadi, 363 ta yaratiladi', () {
      final plan = buildPlan(parseSheet(bytes, _sheetRaw), _rawMapping());

      expect(plan.toCreate.length, 363);
      expect(plan.skipped.length, 38);

      final byReason = plan.skippedByReason;
      expect(byReason[SkipReasons.noName], 37);
      expect(byReason[SkipReasons.duplicateSku], 1);

      // 401 ta ma'lumot qatori: 363 + 37 + 1
      expect(parseSheet(bytes, _sheetRaw).rows.length, 402);
    });

    test("L 001/2 to'liq to'ldiriladi (720 kun, ikkala atribut)", () {
      final plan = buildPlan(parseSheet(bytes, _sheetRaw), _rawMapping());
      final item = plan.toCreate.firstWhere((p) => p.sku == 'L 001/2');

      expect(item.name,
          'Sodium laureth sulfate / Лаурет сульфат натрия');
      expect(item.unit, 'kg');
      expect(item.defaultShelfLifeDays, 720);
      expect(item.attributes['storage_temperature'], 'мин.15-пл.50');
      expect(item.attributes['usage_purpose'],
          'шампунь и жидкое мыло, краска');

      final body = item.toBody();
      expect(body['sku'], 'L 001/2');
      expect(body['default_shelf_life_days'], 720);
      expect(body.containsKey('category_id'), isFalse);
    });

    test("F 164 ikkinchi qatori 'Faylda takrorlangan SKU' bilan otkaziladi", () {
      final plan = buildPlan(parseSheet(bytes, _sheetRaw), _rawMapping());

      final dup = plan.skipped
          .where((s) => s.reason == SkipReasons.duplicateSku)
          .toList();
      expect(dup.length, 1);
      expect(dup.first.sku, 'F 164');
      expect(dup.first.rowNumber, 306);
      expect(plan.toCreate.where((p) => p.sku == 'F 164').length, 1);
    });

    test("Nomi yo'q qatorlar SKU'si saqlangan holda otkaziladi", () {
      final plan = buildPlan(parseSheet(bytes, _sheetRaw), _rawMapping());
      final noName = plan.skipped
          .where((s) => s.reason == SkipReasons.noName)
          .toList();

      expect(noName.length, 37);
      expect(noName.every((s) => s.name.isEmpty), isTrue);
      expect(noName.any((s) => s.sku.isNotEmpty), isTrue);
    });

    test("Bo'sh muddat/harorat hujayralari xatosiz o'tadi", () {
      final plan = buildPlan(parseSheet(bytes, _sheetRaw), _rawMapping());

      // 57-qator: nomi bor, E (muddat) va F (harorat) bo'sh
      final l305 = plan.toCreate.firstWhere((p) => p.sku == 'L 305');
      expect(l305.defaultShelfLifeDays, isNull);
      expect(l305.toBody().containsKey('default_shelf_life_days'), isFalse);
      expect(l305.attributes.containsKey('storage_temperature'), isFalse);
      expect(l305.attributes['usage_purpose'], 'Не используется');

      // 7-qator: nomi bor, muddat 24 oy, F (harorat) bo'sh
      final l009 = plan.toCreate.firstWhere((p) => p.sku == 'L 009');
      expect(l009.defaultShelfLifeDays, 720);
      expect(l009.attributes.containsKey('storage_temperature'), isFalse);
      expect(l009.attributes['usage_purpose'], 'Не используется');

      // 79-qator: nomi bor, D/E/F hammasi bo'sh
      final l012 = plan.toCreate.firstWhere((p) => p.sku == 'L 012');
      expect(l012.attributes, isEmpty);
      expect(l012.defaultShelfLifeDays, isNull);
    });
  });

  group('Plyonka varaqi (sarlavhasiz)', () {
    test('65 ta yaratiladi, birinchisi PLK-403 / Плёнкалар', () {
      final plan = buildPlan(parseSheet(bytes, _sheetFilm), _filmMapping());

      expect(plan.toCreate.length, 65);
      expect(plan.skipped, isEmpty);

      final first = plan.toCreate.first;
      expect(first.sku, 'PLK-403');
      expect(first.name, 'Плёнкалар');
      expect(first.rowNumber, 1);
    });

    test('seriya ustuni A (403..467) dan SKU yig\'iladi', () {
      final plan = buildPlan(parseSheet(bytes, _sheetFilm), _filmMapping());

      expect(plan.toCreate.first.sku, 'PLK-403');
      expect(plan.toCreate.last.sku, 'PLK-467');
      expect(
        plan.toCreate.map((p) => p.sku).toSet().length,
        65,
        reason: 'SKU\'lar takrorlanmasligi kerak',
      );
    });

    test("Bo'sh E/F hujayrali qatorlar o'tadi, bor qatorlar atribut oladi", () {
      final plan = buildPlan(parseSheet(bytes, _sheetFilm), _filmMapping());

      // 26-qator: E=24 oy bor, F (harorat) bo'sh -> atribut yo'q
      final row26 = plan.toCreate.firstWhere((p) => p.sku == 'PLK-428');
      expect(row26.name, 'плёнка для груп упаковки мыла 90гр 242 мм');
      expect(row26.defaultShelfLifeDays, 720);
      expect(row26.attributes, isEmpty);

      // 20-qator: E=24 oy, F = 'пл. 5°C - пл. 25°C'
      final row20 = plan.toCreate.firstWhere((p) => p.sku == 'PLK-422');
      expect(row20.name, 'Маска 3d');
      expect(row20.defaultShelfLifeDays, 720);
      expect(row20.attributes['storage_temperature'], 'пл. 5°C - пл. 25°C');
    });
  });

  group('Sof mantiq qoidalari', () {
    test('sarlavhasiz rejimda 1-qator ham ma\'lumot', () {
      final plan = buildPlan(parseSheet(bytes, _sheetFilm), _filmMapping());
      expect(plan.toCreate.any((p) => p.rowNumber == 1), isTrue);
    });

    test('columnLetter 0..25 -> A..Z', () {
      expect(ParsedSheet.columnLetter(0), 'A');
      expect(ParsedSheet.columnLetter(1), 'B');
      expect(ParsedSheet.columnLetter(5), 'F');
      expect(ParsedSheet.columnLetter(25), 'Z');
      expect(ParsedSheet.columnLetter(26), 'AA');
    });

    test('SKU ustuni tanlangan va bo\'sh bo\'lsa -> "SKU yo\'q"', () {
      const sheet = ParsedSheet(
        name: 'test',
        columnCount: 2,
        rows: [
          ['A-1', 'Nomi bir'],
          ['', 'Nomi ikki'],
        ],
      );
      final plan = buildPlan(
        sheet,
        const ImportMapping(hasHeaderRow: false, nameColumn: 1, skuColumn: 0),
      );

      expect(plan.toCreate.length, 1);
      expect(plan.toCreate.single.sku, 'A-1');
      expect(plan.skipped.single.reason, SkipReasons.noSku);
      expect(plan.skipped.single.rowNumber, 2);
    });

    test('hesob kitob: 6 oy = 180 kun, kun holda o\'zgarishsiz', () {
      const sheet = ParsedSheet(
        name: 'test',
        columnCount: 2,
        rows: [
          ['6', 'Nomi'],
        ],
      );
      final months = buildPlan(
        sheet,
        const ImportMapping(
            hasHeaderRow: false,
            nameColumn: 1,
            shelfLifeColumn: 0,
            shelfLifeInMonths: true),
      );
      final days = buildPlan(
        sheet,
        const ImportMapping(
            hasHeaderRow: false, nameColumn: 1, shelfLifeColumn: 0),
      );

      expect(months.toCreate.single.defaultShelfLifeDays, 180);
      expect(days.toCreate.single.defaultShelfLifeDays, 6);
    });

    test('parslab bo\'lmagan muddat -> null (xato emas)', () {
      const sheet = ParsedSheet(
        name: 'test',
        columnCount: 2,
        rows: [
          ['o\'ylab chiqing', 'Nomi'],
        ],
      );
      final plan = buildPlan(
        sheet,
        const ImportMapping(
            hasHeaderRow: false, nameColumn: 1, shelfLifeColumn: 0),
      );

      expect(plan.toCreate.length, 1);
      expect(plan.toCreate.single.defaultShelfLifeDays, isNull);
    });

    test('nom tanlanmagan/null bo\'lsa hech narsa yaratilmaydi', () {
      final plan = buildPlan(
        parseSheet(bytes, _sheetRaw),
        const ImportMapping(hasHeaderRow: true, nameColumn: 99),
      );

      expect(plan.toCreate, isEmpty);
      expect(plan.skipped.length, 401);
    });
  });
}
