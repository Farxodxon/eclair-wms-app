import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/core/offline/offline_store.dart';
import 'package:wms_app/core/offline/queued_op.dart';
import 'package:wms_app/core/offline/sync_engine.dart';

QueuedOp _op({
  required String id,
  int userId = 1,
  String status = 'pending',
  String createdAt = '2026-01-01T00:00:00Z',
}) {
  return QueuedOp(
    id: id,
    userId: userId,
    type: 'out',
    path: '/inventory/out',
    body: {'batch_container_id': 1, 'quantity': 10},
    label: '$id | 10 kg',
    createdAt: createdAt,
    status: status,
  );
}

void main() {
  late Directory dir;
  late OfflineStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wms_offline_engine_');
    store = OfflineStore(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('2xx amalni ochiradi va tartibni saqlaydi', () async {
    await store.addOp(_op(id: 'a', createdAt: '2026-01-01T00:00:01Z'));
    await store.addOp(_op(id: 'b', createdAt: '2026-01-01T00:00:02Z'));

    final calls = <String>[];
    final engine = SyncEngine(store, (op) async {
      calls.add(op.id);
      return RawResponse(200, {'ok': true});
    });

    final result = await engine.flush(1);
    expect(result.sent, 2);
    expect(result.failed, 0);
    expect(calls, ['a', 'b']);
    expect(await store.loadOps(), isEmpty);
  });

  test('NetworkUnavailable to\'xtatadi va amallarni qoldiradi', () async {
    await store.addOp(_op(id: 'a'));
    await store.addOp(_op(id: 'b', createdAt: '2026-01-01T00:00:02Z'));

    var calls = 0;
    final engine = SyncEngine(store, (op) async {
      calls++;
      throw NetworkUnavailable('Serverga ulanib bolmadi');
    });

    final result = await engine.flush(1);
    expect(result.networkDown, true);
    expect(result.sent, 0);
    expect(calls, 1);
    expect((await store.loadOps()).length, 2);
  });

  test("400 amalni failed qiladi va keyingisiga o'tadi", () async {
    await store.addOp(_op(id: 'a', createdAt: '2026-01-01T00:00:01Z'));
    await store.addOp(_op(id: 'b', createdAt: '2026-01-01T00:00:02Z'));

    final engine = SyncEngine(store, (op) async {
      if (op.id == 'a') {
        return RawResponse(400, {'error': 'invalid_request'});
      }
      return RawResponse(200, {'ok': true});
    });

    final result = await engine.flush(1);
    expect(result.failed, 1);
    expect(result.sent, 1);

    final ops = await store.loadOps();
    expect(ops.length, 1);
    expect(ops.first.id, 'a');
    expect(ops.first.status, 'failed');
    expect(ops.first.error, contains("to'g'ri"));
  });

  test('401 needLogin qaytaradi va amalni qoldiradi', () async {
    await store.addOp(_op(id: 'a'));

    var calls = 0;
    final engine = SyncEngine(store, (op) async {
      calls++;
      return RawResponse(401, {'error': 'unauthorized'});
    });

    final result = await engine.flush(1);
    expect(result.needLogin, true);
    expect(calls, 1);
    expect((await store.loadOps()).single.status, 'pending');
  });

  test("409 request_in_progress 3 daqiqadan keyin uncertain bo'ladi", () async {
    await store.addOp(_op(id: 'a'));

    var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final engine = SyncEngine(
      store,
      (op) async => RawResponse(409, {'error': 'request_in_progress'}),
      now: () => now,
    );

    final first = await engine.flush(1);
    expect(first.sent, 0);
    var ops = await store.loadOps();
    expect(ops.single.status, 'pending');
    expect(ops.single.inProgressSince, isNotNull);

    now = now.add(const Duration(minutes: 2));
    await engine.flush(1);
    ops = await store.loadOps();
    expect(ops.single.status, 'pending');

    now = now.add(const Duration(minutes: 2));
    await engine.flush(1);
    ops = await store.loadOps();
    expect(ops.single.status, 'uncertain');
    expect(ops.single.error, isNotNull);
  });

  test("boshqa userId amali tegilmaydi", () async {
    await store.addOp(_op(id: 'other', userId: 2));

    var calls = 0;
    final engine = SyncEngine(store, (op) async {
      calls++;
      return RawResponse(200, {'ok': true});
    });

    final result = await engine.flush(1);
    expect(result.sent, 0);
    expect(calls, 0);
    expect((await store.loadOps()).single.id, 'other');
  });
}
