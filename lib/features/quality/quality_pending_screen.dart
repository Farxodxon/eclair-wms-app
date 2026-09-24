import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/quality/quality_history_screen.dart';

final qualityPendingProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getQualityPending(auth.token!)
      : Future.value(const []);
});

class QualityPendingScreen extends ConsumerWidget {
  const QualityPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(qualityPendingProvider);
    final canManage = ref.watch(authProvider).canManageQuality;

    return Scaffold(
      appBar: AppBar(title: const Text('Sifat tekshiruvi')),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Xatolik: $err')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fact_check, color: Colors.green, size: 64),
                  SizedBox(height: 12),
                  Text(
                    "Tekshiruv kutayotgan partiya yo'q",
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _PendingBatchCard(
                item: items[index] as Map<String, dynamic>,
                canManage: canManage,
              );
            },
          );
        },
      ),
    );
  }
}

class _PendingBatchCard extends ConsumerWidget {
  const _PendingBatchCard({required this.item, required this.canManage});

  final Map<String, dynamic> item;
  final bool canManage;

  Future<void> _showStatusDialog(
    BuildContext context,
    WidgetRef ref, {
    required String status,
    required String title,
  }) async {
    final batchId = item['batch_id'] as int;

    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(title: title),
    );
    if (note == null || note.isEmpty) return;

    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null || !context.mounted) return;

    try {
      await ApiClient().setQualityStatus(token, batchId, status, note);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Holat "$title" ga o\'zgartirildi')),
      );
      ref.invalidate(qualityPendingProvider);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xatolik: ${e.message}')),
      );
    }
  }

  void _openHistory(BuildContext context) {
    final batchId = item['batch_id'] as int;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QualityHistoryScreen(
          batchId: batchId,
          productName: (item['product_name'] as String?) ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (item['product_name'] as String?) ?? '';
    final lotNumber = (item['lot_number'] as String?) ?? '';
    final status = (item['quality_status'] as String?) ?? '';
    final receivedDate = (item['received_date'] as String?) ?? '-';
    final totalQuantity = (item['total_active_quantity'] as num?) ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 8),
            Text('Lot: $lotNumber | Qabul: $receivedDate'),
            const SizedBox(height: 4),
            Text(
              '$totalQuantity jami',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            if (canManage)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Tasdiqlash'),
                    onPressed: () => _showStatusDialog(
                      context,
                      ref,
                      status: 'approved',
                      title: 'Partiyani tasdiqlash',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrange.shade100,
                      foregroundColor: Colors.deepOrange.shade800,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.report, size: 16),
                    label: const Text('Karantinga qo\'yish'),
                    onPressed: () => _showStatusDialog(
                      context,
                      ref,
                      status: 'quarantine',
                      title: 'Karantinga qo\'yish',
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rad etish'),
                    onPressed: () => _showStatusDialog(
                      context,
                      ref,
                      status: 'rejected',
                      title: 'Partiyani rad etish',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tarix',
                    icon: const Icon(Icons.history),
                    onPressed: () => _openHistory(context),
                  ),
                ],
              )
            else
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Tarix',
                    icon: const Icon(Icons.history),
                    onPressed: () => _openHistory(context),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = qualityStatusLabel(status);
    final Color bg;
    final Color fg;
    switch (status) {
      case 'pending_inspection':
        bg = Colors.blueGrey.shade100;
        fg = Colors.blueGrey.shade800;
      case 'quarantine':
        bg = Colors.deepOrange.shade100;
        fg = Colors.deepOrange.shade800;
      case 'approved':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
      case 'rejected':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title});

  final String title;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Izoh (majburiy)',
          hintText: "O'zgartirish sababini kiriting",
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor qilish'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          child: const Text('Yuborish'),
        ),
      ],
    );
  }
}