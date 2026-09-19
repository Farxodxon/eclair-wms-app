import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/batch_containers_screen.dart';

final productBatchesProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, productId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getBatches(auth.token!, productId)
      : Future.value([]);
});

final productLocationsProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, productId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getProductLocations(auth.token!, productId)
      : Future.value([]);
});

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Map<String, dynamic> product;

  int get productId => product['id'] as int;

  void _showLocations(BuildContext context, WidgetRef ref) {
    ref.invalidate(productLocationsProvider(productId));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductLocationsSheet(productId: productId),
    );
  }

  Future<void> _addBatch(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _BatchFormDialog(productId: productId),
    );
    if (created == true) {
      ref.invalidate(productBatchesProvider(productId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = product['name'] ?? '';
    final sku = product['sku'] ?? '';
    final attributes = product['attributes'];
    final entries = attributes is Map
        ? attributes.entries.toList()
        : const <MapEntry<dynamic, dynamic>>[];

    final batchesAsync = ref.watch(productBatchesProvider(productId));

    return Scaffold(
      appBar: AppBar(title: Text('$name', overflow: TextOverflow.ellipsis)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('SKU: $sku'),
                  if (product['category_name'] != null)
                    Text('Kategoriya: ${product['category_name']}'),
                  if (product['unit'] != null)
                    Text('Birlik: ${product['unit']}'),
                  if (entries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Atributlar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final e in entries)
                      Text('${e.key}: ${e.value}'),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showLocations(context, ref),
                      icon: const Icon(Icons.place),
                      label: const Text('Qayerda?'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Partiyalar (FEFO)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _addBatch(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text("Partiya"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: batchesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Xatolik: $err')),
              data: (batches) {
                if (batches.isEmpty) {
                  return const Center(
                    child: Text(
                      'Partiyalar topilmadi',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: batches.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final batch = batches[index] as Map<String, dynamic>;
                    final expiry = _parseDate(batch['expiry_date']);
                    final daysLeft =
                        expiry?.difference(DateTime.now()).inDays;
                    final urgent = daysLeft != null && daysLeft < 30;
                    final expired = daysLeft != null && daysLeft < 0;
                    final color = expired
                        ? Colors.red
                        : (urgent ? Colors.orange.shade800 : null);
                    return ListTile(
                      leading: Icon(
                        Icons.inventory_2_outlined,
                        color: color,
                      ),
                      title: Text(
                        batch['lot_number'] ?? '',
                        style: TextStyle(
                          color: color,
                          fontWeight: urgent ? FontWeight.bold : null,
                        ),
                      ),
                      subtitle: Text(
                        'Muddat: ${batch['expiry_date'] ?? '-'}'
                        '${urgent ? '  !!!' : ''}',
                      ),
                      trailing: Text(
                        '${batch['total_quantity'] ?? 0}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BatchContainersScreen(
                            batch: batch,
                            productId: productId,
                          ),
                        ),
                      ),
                    );
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

DateTime? _parseDate(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

class _ProductLocationsSheet extends ConsumerWidget {
  const _ProductLocationsSheet({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(productLocationsProvider(productId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Qayerda?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: locationsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Xatolik: $err')),
                data: (locations) {
                  if (locations.isEmpty) {
                    return const Center(
                      child: Text(
                        "Hozircha joylashuv yo'q",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: locations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final loc = locations[index] as Map<String, dynamic>;
                      final warehouse = loc['warehouse_name'] ?? '-';
                      final zone = loc['zone_name'] ?? '-';
                      return ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          '$warehouse -> $zone -> ${loc['location_code']}',
                        ),
                        subtitle: Text(
                          'Lot: ${loc['lot_number'] ?? '-'} | '
                          'Muddat: ${loc['expiry_date'] ?? '-'}',
                        ),
                        trailing: Text(
                          '${loc['quantity'] ?? 0}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BatchFormDialog extends ConsumerStatefulWidget {
  const _BatchFormDialog({required this.productId});

  final int productId;

  @override
  ConsumerState<_BatchFormDialog> createState() => _BatchFormDialogState();
}

class _BatchFormDialogState extends ConsumerState<_BatchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _lotController = TextEditingController();
  DateTime? _manufactureDate;
  DateTime? _expiryDate;
  String _qualityStatus = 'approved';
  String? _error;
  bool _saving = false;

  static const _statuses = [
    'pending_inspection',
    'approved',
    'quarantine',
    'rejected',
  ];

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _pickDate(bool isManufacture) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isManufacture ? _manufactureDate : _expiryDate) ??
          DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isManufacture) {
          _manufactureDate = picked;
        } else {
          _expiryDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final body = <String, dynamic>{
        'lot_number': _lotController.text.trim(),
        if (_manufactureDate != null)
          'manufacture_date': _fmt(_manufactureDate!),
        if (_expiryDate != null) 'expiry_date': _fmt(_expiryDate!),
        'quality_status': _qualityStatus,
      };
      await ApiClient().createBatch(auth.token!, widget.productId, body);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Partiya qo'shish"),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _lotController,
                decoration: const InputDecoration(
                  labelText: 'Lot raqami',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Lot majburiy' : null,
              ),
              const SizedBox(height: 12),
              _dateRow(
                'Ishlab chiqarilgan sana',
                _manufactureDate,
                () => _pickDate(true),
              ),
              const SizedBox(height: 12),
              _dateRow('Muddat', _expiryDate, () => _pickDate(false)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _qualityStatus,
                decoration: const InputDecoration(
                  labelText: 'Sifat holati',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in _statuses)
                    DropdownMenuItem<String>(value: s, child: Text(s)),
                ],
                onChanged: (v) =>
                    setState(() => _qualityStatus = v ?? 'approved'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor qilish'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Saqlash'),
        ),
      ],
    );
  }

  Widget _dateRow(String label, DateTime? value, VoidCallback onTap) {
    return Row(
      children: [
        Expanded(
          child: Text(
            value != null ? '$label: ${_fmt(value)}' : label,
          ),
        ),
        TextButton(onPressed: onTap, child: const Text('Tanlash')),
      ],
    );
  }
}