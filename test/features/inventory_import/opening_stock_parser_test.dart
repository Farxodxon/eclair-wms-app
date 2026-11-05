import 'package:flutter_test/flutter_test.dart';
import 'package:wms_app/features/inventory_import/opening_stock_parser.dart';
import 'package:wms_app/features/products/import/import_planner.dart';

ParsedSheet _sheet(List<List<String>> rows) {
  return ParsedSheet(
    name: 'Qoldiq',
    rows: rows,
    columnCount: rows.isEmpty ? 0 : rows.first.length,
  );
}

const _header = [
  'Kod',
  'Nomi',
  'Kategoriya',
  'Idish turi',
  'Idish soni',
  '1 idish, kg',
  'Lot raqami',
  'Yaroqlilik muddati',
  'Joylashuv kodi',
  'Yaroqlilik (oy)',
];

void main() {
  test('asosiy ustunlarni o\'qiydi va qiymatlarni tozalaydi', () {
    final result = parseOpeningStockRows(
      _sheet([
        _header,
        [
          'L 001/2',
          'L 001/2 nomi',
          'Xom ashiyo',
          'Kanistr',
          '2',
          '25',
          'LOT-1',
          '15.03.2027',
          'A-01-2-3',
          '24',
        ],
      ]),
    );

    expect(result.sheetName, 'Qoldiq');
    expect(result.rows, hasLength(1));
    final row = result.rows.first;
    expect(row.row, 2);
    expect(row.sku, 'L 001/2');
    expect(row.name, 'L 001/2 nomi');
    expect(row.category, 'Xom ashiyo');
    expect(row.containerType, 'Kanistr');
    expect(row.unitCount, 2);
    expect(row.unitWeightKg, 25);
    expect(row.lotNumber, 'LOT-1');
    expect(row.expiryDate, '2027-03-15');
    expect(row.locationCode, 'A-01-2-3');
    expect(row.shelfLifeMonths, 24);
  });

  test('kirill sarlavhalarini moslashtiradi', () {
    final result = parseOpeningStockRows(
      _sheet([
        [
          '\u041a\u043e\u0434',
          '\u041d\u0430\u0437\u0432\u0430\u043d\u0438\u0435',
          '\u041a\u043e\u043b\u0438\u0447\u0435\u0441\u0442\u0432\u043e',
          '\u0412\u0435\u0441',
        ],
        ['C 045', 'Qop', '3', '20'],
      ]),
    );

    final row = result.rows.first;
    expect(row.sku, 'C 045');
    expect(row.name, 'Qop');
    expect(row.unitCount, 3);
    expect(row.unitWeightKg, 20);
  });

  test('sarlavha to\'liq mos kelishi shart, qisman moslik yo\'q', () {
    expect(
      () => parseOpeningStockRows(
        _sheet([
          ['Kod tovara', 'Nomi', 'Idish soni'],
          ['X 1', 'Nom', '5'],
        ]),
      ),
      throwsA(
        isA<OpeningStockParseException>().having(
          (e) => e.message,
          'message',
          contains('kod (SKU)'),
        ),
      ),
    );
  });

  test('idish soni ustuni bo\'lmasa aniq xabar beradi', () {
    expect(
      () => parseOpeningStockRows(
        _sheet([
          ['Kod', 'Nomi'],
          ['X 1', 'Nom'],
        ]),
      ),
      throwsA(
        isA<OpeningStockParseException>().having(
          (e) => e.message,
          'message',
          contains('idish soni'),
        ),
      ),
    );
  });

  test('butunlay bo\'sh qatorlarni tashlaydi va Excel qatorini saqlaydi', () {
    final result = parseOpeningStockRows(
      _sheet([
        _header,
        ['', '', '', '', '', '', '', '', '', ''],
        ['L 001/2', 'Nom', '', '', '2', '25', '', '', '', ''],
      ]),
    );

    expect(result.rows, hasLength(1));
    expect(result.rows.first.row, 3);
  });

  test('vergulli son va vaqtli sanani o\'qiydi', () {
    final result = parseOpeningStockRows(
      _sheet([
        _header,
        [
          'L 001/2',
          'Nom',
          '',
          '',
          '2,5',
          '20,5',
          '',
          '2027-03-15 00:00:00.000',
          '',
          '',
        ],
      ]),
    );

    final row = result.rows.first;
    expect(row.unitCount, 2.5);
    expect(row.unitWeightKg, 20.5);
    expect(row.expiryDate, '2027-03-15');
  });

  test('Srok godnosti ustunini muddat deb o\'qiydi', () {
    final result = parseOpeningStockRows(
      _sheet([
        [
          'Kod',
          'Idish soni',
          '\u0421\u0440\u043e\u043a \u0433\u043e\u0434\u043d\u043e\u0441\u0442\u0438',
        ],
        ['C 045', '3', '01.12.2027'],
      ]),
    );

    expect(result.rows.first.expiryDate, '2027-12-01');
  });

  test('noto\'g\'ri sanani o\'zgartirmaydi (server rad etadi)', () {
    final result = parseOpeningStockRows(
      _sheet([
        _header,
        ['L 001/2', 'Nom', '', '', '2', '25', '', '31.02.2027', '', ''],
      ]),
    );

    expect(result.rows.first.expiryDate, '31.02.2027');
  });
}
