import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/core/offline/offline_store.dart';
import 'package:wms_app/core/offline/queued_op.dart';

typedef OpSender = Future<RawResponse> Function(QueuedOp op);

class FlushResult {
  const FlushResult({
    this.sent = 0,
    this.failed = 0,
    this.networkDown = false,
    this.needLogin = false,
  });

  final int sent;
  final int failed;
  final bool networkDown;
  final bool needLogin;
}

const _uncertainMessage =
    "Server javobi noaniq. Qoldiq va tarixni tekshiring, kerak bo'lsa "
    "amalni o'chiring";

class SyncEngine {
  SyncEngine(this.store, this.send, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final OfflineStore store;
  final OpSender send;
  final DateTime Function() _now;

  Future<FlushResult> flush(int userId) async {
    var sent = 0;
    var failed = 0;
    var networkDown = false;
    var needLogin = false;

    final all = await store.loadOps();
    final mine = all
        .where((op) => op.userId == userId && op.status == 'pending')
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final op in mine) {
      RawResponse response;
      try {
        response = await send(op);
      } on NetworkUnavailable {
        networkDown = true;
        break;
      }

      if (response.ok) {
        await store.removeOp(op.id);
        sent++;
        continue;
      }

      if (response.statusCode == 401) {
        needLogin = true;
        break;
      }

      if (response.statusCode == 409 &&
          response.errorCode == 'request_in_progress') {
        if (op.inProgressSince == null) {
          await store.updateOp(
            op.copyWith(inProgressSince: _now().toUtc().toIso8601String()),
          );
        } else {
          final started = DateTime.tryParse(op.inProgressSince!);
          if (started != null &&
              _now().toUtc().difference(started) > const Duration(minutes: 3)) {
            await store.updateOp(
              op.copyWith(status: 'uncertain', error: _uncertainMessage),
            );
          }
        }
        continue;
      }

      if (response.statusCode >= 500 ||
          response.statusCode == 429 ||
          response.statusCode == 408) {
        await store.updateOp(op.copyWith(attempts: op.attempts + 1));
        break;
      }

      await store.updateOp(
        op.copyWith(
          status: 'failed',
          error: ApiClient().errorMessageFor(response),
        ),
      );
      failed++;
    }

    return FlushResult(
      sent: sent,
      failed: failed,
      networkDown: networkDown,
      needLogin: needLogin,
    );
  }
}
