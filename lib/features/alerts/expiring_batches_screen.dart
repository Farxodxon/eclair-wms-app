import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/product_detail_screen.dart';

final expiringBatchesProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, days) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getExpiringBatches(auth.token!, days: days)
      : Future.value({'days': days, 'items': []});
});

class ExpiringBatchesScreen extends ConsumerStatefulWidget {
  const ExpiringBatchesScreen({super.key});

  @override
  ConsumerState<ExpiringBatchesScreen> createState() =>
      _ExpiringBatchesScreenState();
}

class _ExpiringBatchesScreenState extends ConsumerState<ExpiringBatchesScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(expiringBatchesProvider(_days));

    return Scaffold(
      appBar: AppBar(title: const Text('Ogohlantirishlar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 kun')),
                    ButtonSegment(value: 30, label: Text('30 kun')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (selection) {
                    setState(() => _days = selection.first);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: batchesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Xatolik: $err')),
              data: (data) {
                final items = (data['items'] as List<dynamic>? ?? [])
                    .cast<Map<String, dynamic>>();
                if (items.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 64,
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Muddati yaqinlashgan mahsulot yo'q",
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
                    return _ExpiryBatchCard(item: items[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryBatchCard extends StatelessWidget {
  const _ExpiryBatchCard({required this.item});

  final Map<String, dynamic> item;

  String get _urgency => (item['urgency'] as String?) ?? 'warning';

  Color get _borderColor {
    switch (_urgency) {
      case 'expired':
        return Colors.red;
      case 'critical':
        return Colors.orange.shade800;
      default:
        return Colors.amber.shade600;
    }
  }

  Color get _fillColor {
    switch (_urgency) {
      case 'expired':
        return Colors.red.shade50;
      case 'critical':
        return Colors.orange.shade50;
      default:
        return Colors.amber.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (item['product_name'] as String?) ?? '';
    final lotNumber = (item['lot_number'] as String?) ?? '';
    final expiryDate = (item['expiry_date'] as String?) ?? '-';
    final daysRemaining = (item['days_remaining'] as num?)?.toInt() ?? 0;
    final totalQuantity = (item['total_active_quantity'] as num?) ?? 0;
    final locations = (item['locations'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final productId = item['product_id'];

    final daysLabel = daysRemaining < 0
        ? '${-daysRemaining} kun o\'tdi'
        : daysRemaining == 0
            ? 'Bugun tugaydi'
            : '$daysRemaining kun qoldi';

    final locationsBrief = locations
        .map((l) => '${l['warehouse_name']} / ${l['location_code']}: '
            '${l['quantity']}')
        .join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: _fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _borderColor),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_urgency != 'warning')
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _borderColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _urgency == 'expired' ? "Muddati o'tgan" : 'Shoshilinch',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Lot: $lotNumber | Muddat: $expiryDate | $daysLabel'),
            if (locationsBrief.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                locationsBrief,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$totalQuantity',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _urgency == 'expired'
                    ? Colors.red
                    : (_urgency == 'critical'
                        ? Colors.orange.shade800
                        : Colors.amber.shade900),
              ),
            ),
            const Text('jami', style: TextStyle(fontSize: 12)),
          ],
        ),
        onTap: productId is int
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(
                      product: {
                        'id': productId,
                        'name': name,
                      },
                    ),
                  ),
                )
            : null,
      ),
    );
  }
}