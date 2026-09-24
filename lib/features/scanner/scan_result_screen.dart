import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/product_detail_screen.dart';

enum ScanResultType { container, product }

class ScanResultScreen extends ConsumerWidget {
  const ScanResultScreen({
    super.key,
    required this.type,
    required this.data,
  });

  final ScanResultType type;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(type == ScanResultType.container ? 'Konteyner' : 'Mahsulot'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: type == ScanResultType.container
                ? _ContainerCard(container: data)
                : _ProductCard(product: data),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (type == ScanResultType.container)
                    FilledButton.icon(
                      onPressed: () => _showOutDialog(context, ref),
                      icon: const Icon(Icons.logout),
                      label: const Text('Chiqarish (OUT)'),
                    ),
                  if (type == ScanResultType.product) ...[
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: data),
                        ),
                      ),
                      icon: const Icon(Icons.inventory_2),
                      label: const Text('Mahsulot sahifasiga o\'tish'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (type == ScanResultType.container)
                    const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Yana skanerlash'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOutDialog(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _OutDialog(container: data),
    );
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ContainerCard extends StatelessWidget {
  const _ContainerCard({required this.container});

  final Map<String, dynamic> container;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                container['container_barcode'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _InfoTile(
                label: 'Mahsulot',
                value: container['product_name'] ?? '-',
              ),
              _InfoTile(
                label: 'SKU',
                value: container['product_sku'] ?? '-',
              ),
              _InfoTile(label: 'Lot', value: container['lot_number'] ?? '-'),
              _InfoTile(
                label: 'Muddat',
                value: container['expiry_date'] ?? '-',
              ),
              _InfoTile(
                label: 'Sifat',
                value: container['quality_status'] ?? '-',
              ),
              _InfoTile(
                label: 'Joylashuv',
                value: container['location_code'] ?? '-',
              ),
              _InfoTile(
                label: 'Ombor',
                value: container['warehouse_name'] ?? '-',
              ),
              _InfoTile(
                label: 'Joriy miqdor',
                value: '${container['quantity'] ?? 0}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final attributes = product['attributes'];
    final entries = attributes is Map
        ? attributes.entries.toList()
        : const <MapEntry<dynamic, dynamic>>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product['name'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _InfoTile(label: 'Nomi', value: product['name'] ?? '-'),
              _InfoTile(label: 'SKU', value: product['sku'] ?? '-'),
              _InfoTile(label: 'Shtrix kod', value: product['barcode'] ?? '-'),
              if (product['category_name'] != null)
                _InfoTile(
                  label: 'Kategoriya',
                  value: product['category_name'],
                ),
              if (product['unit'] != null)
                _InfoTile(label: 'Birlik', value: product['unit']),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Atributlar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final e in entries)
                  _InfoTile(label: '${e.key}', value: '${e.value}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OutDialog extends ConsumerStatefulWidget {
  const _OutDialog({required this.container});

  final Map<String, dynamic> container;

  @override
  ConsumerState<_OutDialog> createState() => _OutDialogState();
}

class _OutDialogState extends ConsumerState<_OutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
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
      final quantity = num.parse(_quantityController.text.trim());
      final result = await ApiClient().inventoryOut(auth.token!, {
        'batch_container_id': widget.container['id'],
        'quantity': quantity,
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
      });
      final remaining = result['remaining_quantity'] ?? result['quantity'];
      if (mounted) {
        Navigator.pop(context, 'Chiqarish bajarildi, qoldi: $remaining');
      }
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
      title: const Text('Chiqarish (OUT)'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.container['container_barcode']} | '
                'mavjud: ${widget.container['quantity']}',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Miqdor',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final parsed = num.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return "Miqdor 0 dan katta bo'lishi kerak";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Izoh (ixtiyoriy)',
                  border: OutlineInputBorder(),
                ),
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
              : const Text('Chiqarish'),
        ),
      ],
    );
  }
}