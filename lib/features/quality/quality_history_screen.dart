import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';

final qualityHistoryProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, batchId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getQualityHistory(auth.token!, batchId)
      : Future.value(const []);
});

String qualityStatusLabel(String status) {
  switch (status) {
    case 'pending_inspection':
      return 'Tekshiruvda';
    case 'approved':
      return 'Tasdiqlangan';
    case 'quarantine':
      return 'Karantin';
    case 'rejected':
      return 'Rad etilgan';
    default:
      return status;
  }
}

class QualityHistoryScreen extends ConsumerWidget {
  const QualityHistoryScreen({
    super.key,
    required this.batchId,
    this.productName,
  });

  final int batchId;
  final String? productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(qualityHistoryProvider(batchId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Partiya tarixi${productName == null ? '' : '  $productName'}',
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Xatolik: $err')),
        data: (history) {
          if (history.isEmpty) {
            return const Center(
              child: Text(
                'Tarix yo\'q',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 16),
            itemBuilder: (context, index) {
              return _HistoryTile(
                entry: history[index] as Map<String, dynamic>,
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final Map<String, dynamic> entry;

  String _formatDate(dynamic raw) {
    final date = DateTime.tryParse(raw as String? ?? '');
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final from = (entry['from_status'] as String?) ?? '';
    final to = (entry['to_status'] as String?) ?? '';
    final note = (entry['note'] as String?) ?? '';
    final changedByName = (entry['changed_by_name'] as String?) ?? '';
    final changedAt = _formatDate(entry['changed_at']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(status: from, isFrom: true),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                _StatusChip(status: to, isFrom: false),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(note, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    changedByName,
                    style: const TextStyle(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  changedAt,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isFrom});

  final String status;
  final bool isFrom;

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
        color: isFrom ? Colors.grey.shade200 : bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isFrom ? Colors.grey.shade700 : fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}