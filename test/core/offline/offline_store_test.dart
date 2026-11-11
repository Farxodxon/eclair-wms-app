import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wms_app/core/offline/offline_store.dart';
import 'package:wms_app/core/offline/queued_op.dart';

QueuedOp _op({
  String id = 'op1',
  int userId = 1,
  String status = 'pending',
  num quantity = 10,
  int containerId = 1,
  String createdAt = '2026-01-01T00:00:00Z',
}) {
  return QueuedOp(
    id: id,
    userId: userId,
    type: 'out',
    path: '/inventory/out',
    body: {'batch_container_id': containerId, 'quantity': quantity},
    label: 'C1 | $quantity kg',
    createdAt: createdAt,
    status: status,
  );
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wms_offline_store_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test("addOp saqlanadi va yangi OfflineStore nusxasi o'qiydi", () async {
    final store = OfflineStore(dir);
    await store.addOp(_op(id: 'a'));

    final again = OfflineStore(dir);
    final ops = await again.loadOps();
    expect(ops.length, 1);
    expect(ops.first.id, 'a');
    expect(ops.first.body['quantity'], 10);
  });

  test("buzuq fayl bo'sh ro'yxat qaytaradi", () async {
    File('${dir.path}/ops.json').writeAsStringSync('{bu json emas');
    final store = OfflineStore(dir);
    expect(await store.loadOps(), isEmpty);
  });

  test('findContainerByBarcode pendingni ayiradi, failed hisobga olinmaydi',
      () async {
    final store = OfflineStore(dir);
    await store.saveSnapshot({
      'generated_at': '2026-01-01T00:00:00Z',
      'containers': [
        {
          'container_id': 5,
          'container_barcode': 'C1',
          'quantity': 100,
          'unit_weight_kg': 25,
          'location_code': 'A-1',
          'sku': 'SKU1',
          'product_name': 'Mahsulot',
          'lot_number': 'LOT-1',
          'expiry_date': '2027-01-01',
          'quality_status': 'approved',
          'location_id': 1,
          'product_id': 9,
          'unit': 'kg',
        },
      ],
    });
    await store.addOp(_op(id: 'p', status: 'pending', quantity: 40, containerId: 5));
    await store.addOp(_op(id: 'f', status: 'failed', quantity: 30, containerId: 5));

    final found = await store.findContainerByBarcode('C1');
    expect(found, isNotNull);
    expect(found!['quantity'], 60);
    expect(found['product_sku'], 'SKU1');
    expect(found['offline'], true);
    expect(found['snapshot_at'], '2026-01-01T00:00:00Z');

    expect(await store.findContainerByBarcode('YOQ'), isNull);
  });
}
