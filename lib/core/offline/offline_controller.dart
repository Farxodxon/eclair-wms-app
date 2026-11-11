import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/core/offline/offline_store.dart';
import 'package:wms_app/core/offline/queued_op.dart';
import 'package:wms_app/core/offline/sync_engine.dart';
import 'package:wms_app/features/auth/auth_provider.dart';

/// SnackBar'larni MaterialApp darajasida ko'rsatish uchun.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

final offlineStoreProvider = FutureProvider<OfflineStore>((ref) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/wms_offline');
  await dir.create(recursive: true);
  return OfflineStore(dir);
});

class OfflineState {
  const OfflineState({
    this.online = true,
    this.syncing = false,
    this.pending = 0,
    this.failed = 0,
    this.needLogin = false,
    this.offlineSince,
    this.lastSnapshotAt,
    this.ops = const [],
  });

  final bool online;
  final bool syncing;
  final int pending;
  final int failed;
  final bool needLogin;
  final DateTime? offlineSince;
  final DateTime? lastSnapshotAt;
  final List<QueuedOp> ops;

  OfflineState copyWith({
    bool? online,
    bool? syncing,
    int? pending,
    int? failed,
    bool? needLogin,
    DateTime? offlineSince,
    DateTime? lastSnapshotAt,
    List<QueuedOp>? ops,
    bool clearOfflineSince = false,
    bool clearLastSnapshot = false,
  }) {
    return OfflineState(
      online: online ?? this.online,
      syncing: syncing ?? this.syncing,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      needLogin: needLogin ?? this.needLogin,
      offlineSince: clearOfflineSince
          ? null
          : (offlineSince ?? this.offlineSince),
      lastSnapshotAt: clearLastSnapshot
          ? null
          : (lastSnapshotAt ?? this.lastSnapshotAt),
      ops: ops ?? this.ops,
    );
  }
}

class SubmitOutcome {
  SubmitOutcome.queued()
      : queued = true,
        data = null;

  SubmitOutcome.sent(this.data) : queued = false;

  final bool queued;
  final Map<String, dynamic>? data;

  bool get sent => !queued;
}

class OfflineController extends StateNotifier<OfflineState> {
  OfflineController(this._ref) : super(const OfflineState()) {
    _ref.listen<AuthState>(
      authProvider,
      (_, next) => _onAuthChanged(next),
      fireImmediately: true,
    );
  }

  final Ref<Object?> _ref;

  Timer? _timer;
  String? _token;
  int? _userId;
  bool _ticking = false;

  Future<OfflineStore> _store() => _ref.read(offlineStoreProvider.future);

  void _onAuthChanged(AuthState auth) {
    if (auth.status == AuthStatus.loggedIn &&
        auth.token != null &&
        auth.user?['id'] is num) {
      _token = auth.token;
      _userId = (auth.user!['id'] as num).toInt();
      unawaited(_bootstrap());
      _timer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(tick());
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _token = null;
      _userId = null;
      if (mounted && state.needLogin) {
        state = state.copyWith(needLogin: false);
      }
    }
  }

  Future<void> _bootstrap() async {
    try {
      await refreshOps();
      await tick();
    } catch (_) {
      // Keyingi tickda qayta uriniladi.
    }
  }

  Future<void> refreshOps() async {
    final store = await _store();
    final all = await store.loadOps();
    final userId = _userId;
    final mine = <QueuedOp>[];
    if (userId != null) {
      for (final op in all) {
        if (op.userId == userId) mine.add(op);
      }
      mine.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final snapshot = await store.loadSnapshot();
    final snapshotAt = _parseDate(snapshot?['generated_at']);
    if (!mounted) return;
    state = state.copyWith(
      ops: mine,
      pending: mine.where((o) => o.status == 'pending').length,
      failed: mine
          .where((o) => o.status == 'failed' || o.status == 'uncertain')
          .length,
      lastSnapshotAt: snapshotAt,
      clearLastSnapshot: snapshotAt == null,
    );
  }

  Future<void> tick() async {
    final token = _token;
    final userId = _userId;
    if (_ticking || token == null || userId == null) return;
    _ticking = true;
    try {
      final api = ApiClient();
      final healthy = await api.probeHealth();
      if (!mounted) return;
      if (!healthy) {
        state = state.copyWith(
          online: false,
          syncing: false,
          offlineSince: state.offlineSince ?? DateTime.now(),
        );
        return;
      }

      state = state.copyWith(online: true, clearOfflineSince: true);
      await refreshOps();
      if (!mounted) return;

      if (state.pending > 0) {
        state = state.copyWith(syncing: true);
        final store = await _store();
        final engine = SyncEngine(
          store,
          (op) => api.rawPost(
            token,
            op.path,
            op.body,
            idempotencyKey: op.id,
          ),
        );
        final result = await engine.flush(userId);
        if (!mounted) return;
        state = state.copyWith(
          syncing: false,
          needLogin: result.needLogin,
          online: !result.networkDown,
          offlineSince:
              result.networkDown ? (state.offlineSince ?? DateTime.now()) : null,
          clearOfflineSince: !result.networkDown,
        );
        await refreshOps();
        if (result.sent > 0) {
          _showMessage('${result.sent} ta amal serverga yuborildi');
        }
        if (result.failed > 0) {
          _showMessage(
            '${result.failed} ta amal yuborilmadi, ro\'yxatni ko\'ring',
          );
        }
      }

      await _maybeRefreshSnapshot(token);
    } catch (_) {
      // Best-effort: keyingi davrda qayta uriniladi.
    } finally {
      _ticking = false;
    }
  }

  Future<void> _maybeRefreshSnapshot(String token) async {
    final store = await _store();
    final snapshot = await store.loadSnapshot();
    final generated = _parseDate(snapshot?['generated_at']);
    final stale = generated == null ||
        DateTime.now().difference(generated) > const Duration(minutes: 10);
    if (state.pending > 0 && !stale) return;
    try {
      final data = await ApiClient().getSyncSnapshot(token);
      await store.saveSnapshot(data);
      if (!mounted) return;
      final at = _parseDate(data['generated_at']);
      state = state.copyWith(
        lastSnapshotAt: at,
        clearLastSnapshot: at == null,
      );
    } catch (_) {
      // Snapshot keyingi safar yangilanadi.
    }
  }

  Future<SubmitOutcome> submitOut(
    Map<String, dynamic> body,
    String label,
  ) async {
    final token = _token;
    final userId = _userId;
    if (token == null || userId == null) {
      throw ApiException('Avval tizimga kiring');
    }

    final opId = newOpId();
    final api = ApiClient();
    RawResponse response;
    try {
      response = await api.rawPost(
        token,
        '/inventory/out',
        body,
        idempotencyKey: opId,
      );
    } on NetworkUnavailable {
      await _enqueue(userId, opId, body, label);
      if (mounted) {
        state = state.copyWith(
          online: false,
          offlineSince: state.offlineSince ?? DateTime.now(),
        );
      }
      return SubmitOutcome.queued();
    }

    if (response.ok) {
      final data = response.data;
      return SubmitOutcome.sent(
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      );
    }
    if (response.statusCode == 401) {
      throw ApiException('Sessiya muddati tugagan, qaytadan kiring');
    }
    if (response.statusCode >= 500 || response.statusCode == 429) {
      await _enqueue(userId, opId, body, label);
      return SubmitOutcome.queued();
    }
    throw ApiException(api.errorMessageFor(response));
  }

  Future<void> _enqueue(
    int userId,
    String opId,
    Map<String, dynamic> body,
    String label,
  ) async {
    final store = await _store();
    final op = QueuedOp(
      id: opId,
      userId: userId,
      type: 'out',
      path: '/inventory/out',
      body: body,
      label: label,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      status: 'pending',
    );
    await store.addOp(op);
    await refreshOps();
  }

  Future<void> deleteOp(String id) async {
    final store = await _store();
    await store.removeOp(id);
    await refreshOps();
  }

  DateTime? _parseDate(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  void _showMessage(String message) {
    rootMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

final offlineControllerProvider =
    StateNotifierProvider<OfflineController, OfflineState>((ref) {
  return OfflineController(ref);
});
