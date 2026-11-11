import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wms_app/core/offline/queued_op.dart';

class OfflineStore {
  OfflineStore(this.dir);

  final Directory dir;

  Future<void> _queue = Future<void>.value();

  File get _opsFile => File('${dir.path}/ops.json');
  File get _snapshotFile => File('${dir.path}/snapshot.json');

  /// Barcha yozishlar bitta ketma-ket navbatdan o'tadi.
  Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((_) {});
    return next;
  }

  Future<List<QueuedOp>> loadOps() async {
    try {
      final file = _opsFile;
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final ops = <QueuedOp>[];
      for (final item in decoded) {
        if (item is Map) {
          ops.add(QueuedOp.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return ops;
    } catch (_) {
      return [];
    }
  }

  Future<void> addOp(QueuedOp op) {
    return _serialize(() async {
      final ops = await loadOps();
      ops.removeWhere((o) => o.id == op.id);
      ops.add(op);
      await _writeJson(_opsFile, ops.map((o) => o.toJson()).toList());
    });
  }

  Future<void> updateOp(QueuedOp op) {
    return _serialize(() async {
      final ops = await loadOps();
      final index = ops.indexWhere((o) => o.id == op.id);
      if (index < 0) return;
      ops[index] = op;
      await _writeJson(_opsFile, ops.map((o) => o.toJson()).toList());
    });
  }

  Future<void> removeOp(String id) {
    return _serialize(() async {
      final ops = await loadOps();
      ops.removeWhere((o) => o.id == id);
      await _writeJson(_opsFile, ops.map((o) => o.toJson()).toList());
    });
  }

  Future<Map<String, dynamic>?> loadSnapshot() async {
    try {
      final file = _snapshotFile;
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSnapshot(Map<String, dynamic> snapshot) {
    return _serialize(() => _writeJson(_snapshotFile, snapshot));
  }

  Future<void> _writeJson(File file, Object data) async {
    await dir.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      // Windows'da mavjud fayl ustiga rename xato beradi.
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }

  Future<Map<String, dynamic>?> findContainerByBarcode(String barcode) async {
    final snapshot = await loadSnapshot();
    if (snapshot == null) return null;
    final containers = snapshot['containers'];
    if (containers is! List) return null;

    Map<String, dynamic>? match;
    for (final item in containers) {
      if (item is Map && item['container_barcode'] == barcode) {
        match = Map<String, dynamic>.from(item);
        break;
      }
    }
    if (match == null) return null;

    final containerId = match['container_id'];
    num quantity = (match['quantity'] as num?) ?? 0;
    final ops = await loadOps();
    for (final op in ops) {
      if (op.status != 'pending') continue;
      if (op.body['batch_container_id'] != containerId) continue;
      final queued = op.body['quantity'];
      if (queued is num) quantity -= queued;
    }
    if (quantity < 0) quantity = 0;

    return <String, dynamic>{
      'id': match['container_id'],
      'container_barcode': match['container_barcode'],
      'quantity': quantity,
      'unit_weight_kg': match['unit_weight_kg'],
      'location_code': match['location_code'],
      'product_sku': match['sku'],
      'product_name': match['product_name'],
      'lot_number': match['lot_number'],
      'expiry_date': match['expiry_date'],
      'quality_status': match['quality_status'],
      'location_id': match['location_id'],
      'product_id': match['product_id'],
      'unit': match['unit'],
      'warehouse_name': null,
      'product_barcode': null,
      'offline': true,
      'snapshot_at': snapshot['generated_at'],
    };
  }
}
