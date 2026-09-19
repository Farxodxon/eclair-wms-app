import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';

final containerTransactionsProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, containerId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient()
          .getInventoryTransactions(auth.token!, batchContainerId: containerId)
      : Future.value([]);
});

const _typeLabels = {
  'OUT': 'Chiqarish (OUT)',
  'TRANSFER': "Ko'chirish (TRANSFER)",
  'ADJUSTMENT': 'Tuzatish (ADJUSTMENT)',
};

Color _typeColor(String type) {
  switch (type) {
    case 'OUT':
      return Colors.red;
    case 'TRANSFER':
      return Colors.blue;
    case 'ADJUSTMENT':
      return Colors.deepOrange;
    default:
      return Colors.grey;
  }
}

class TransactionHistoryScreen extends ConsumerWidget {
  const TransactionHistoryScreen({
    super.key,
    required this.containerId,
    this.barcode,
  });

  final int containerId;
  final String? barcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(containerTransactionsProvider(containerId));

    return Scaffold(
      appBar: AppBar(title: Text('Tarix: ${barcode ?? ''}')),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Xatolik: $err')),
        data: (transactions) {
          if (transactions.isEmpty) {
            return const Center(
              child: Text(
                'Harakatlar topilmadi',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            itemCount: transactions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final t = transactions[index] as Map<String, dynamic>;
              final type = t['type'] ?? '';
              final color = _typeColor(type);
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(
                    type == 'OUT'
                        ? Icons.upload
                        : (type == 'TRANSFER'
                            ? Icons.swap_horiz
                            : Icons.tune),
                    size: 18,
                    color: color,
                  ),
                ),
                title: Text(_typeLabels[type] ?? type),
                subtitle: Text(
                  '${t['note'] ?? ''}'
                  '${t['performed_by_name'] != null ? '\n${t['performed_by_name']}' : ''}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${t['quantity'] ?? 0}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    Text(
                      _fmtTime(t['created_at']),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _fmtTime(dynamic value) {
  if (value == null) return '';
  final dt = DateTime.tryParse(value.toString());
  if (dt == null) return '';
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
