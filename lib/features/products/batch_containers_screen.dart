import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/transaction_history_screen.dart';

final batchContainersProvider =
    FutureProvider.autoDispose.family<List<dynamic>, int>((ref, batchId) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getBatchContainers(auth.token!, batchId)
      : Future.value([]);
});

/// Flat list of storage locations from every warehouse the user can access.
/// Each item gets an extra `warehouse_name` field.
final allStorageLocationsProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.token == null) return <dynamic>[];
  final api = ApiClient();
  final warehouses = await api.getWarehouses(auth.token!);
  final locations = <dynamic>[];
  for (final w in warehouses) {
    final wh = w as Map<String, dynamic>;
    final whId = wh['id'] as int?;
    if (whId == null) continue;
    final locs = await api.getStorageLocations(auth.token!, whId);
    for (final l in locs) {
      if (l is Map) {
        locations.add({
          ...Map<String, dynamic>.from(l),
          'warehouse_name': wh['name'],
        });
      }
    }
  }
  return locations;
});

class BatchContainersScreen extends ConsumerWidget {
  const BatchContainersScreen({
    super.key,
    required this.batch,
    required this.productId,
  });

  final Map<String, dynamic> batch;
  final int productId;

  int get batchId => batch['id'] as int;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containersAsync = ref.watch(batchContainersProvider(batchId));
    final canAdjust = ref.watch(authProvider).canAdjust;

    return Scaffold(
      appBar: AppBar(
        title: Text('Konteynerlar: ${batch['lot_number'] ?? ''}'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showDialog<String>(
            context: context,
            builder: (_) => _ContainerFormDialog(batchId: batchId),
          );
          if (created != null) {
            ref.invalidate(batchContainersProvider(batchId));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text("Konteyner qo'shish"),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lot: ${batch['lot_number'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Muddat: ${batch['expiry_date'] ?? '-'}'),
                  Text('Sifat: ${batch['quality_status'] ?? '-'}'),
                ],
              ),
            ),
          ),
          Expanded(
            child: containersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Xatolik: $err')),
              data: (containers) {
                if (containers.isEmpty) {
                  return const Center(
                    child: Text(
                      'Konteynerlar topilmadi',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: containers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final container =
                        containers[index] as Map<String, dynamic>;
                    return _ContainerTile(
                      container: container,
                      batchId: batchId,
                      canAdjust: canAdjust,
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

class _ContainerTile extends ConsumerWidget {
  const _ContainerTile({
    required this.container,
    required this.batchId,
    required this.canAdjust,
  });

  final Map<String, dynamic> container;
  final int batchId;
  final bool canAdjust;

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _runOut(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _OutDialog(container: container),
    );
    if (message != null && context.mounted) {
      ref.invalidate(batchContainersProvider(batchId));
      _showMessage(context, message);
    }
  }

  Future<void> _runTransfer(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _TransferDialog(container: container),
    );
    if (message != null && context.mounted) {
      ref.invalidate(batchContainersProvider(batchId));
      _showMessage(context, message);
    }
  }

  Future<void> _runAdjust(BuildContext context, WidgetRef ref) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _AdjustDialog(container: container),
    );
    if (message != null && context.mounted) {
      ref.invalidate(batchContainersProvider(batchId));
      _showMessage(context, message);
    }
  }

  void _openHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionHistoryScreen(
          containerId: container['id'] as int,
          barcode: container['container_barcode'] ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.qr_code_2),
      title: Text(container['container_barcode'] ?? ''),
      subtitle: Text(
        'Miqdor: ${container['quantity'] ?? 0} | '
        'Joy: ${container['location_code'] ?? '-'} | '
        '${container['status'] ?? ''}',
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          switch (value) {
            case 'out':
              _runOut(context, ref);
              break;
            case 'transfer':
              _runTransfer(context, ref);
              break;
            case 'adjust':
              _runAdjust(context, ref);
              break;
            case 'history':
              _openHistory(context);
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'out', child: Text('Chiqarish (OUT)')),
          const PopupMenuItem(
              value: 'transfer', child: Text("Ko'chirish (TRANSFER)")),
          if (canAdjust)
            const PopupMenuItem(
                value: 'adjust', child: Text('Tuzatish (ADJUSTMENT)')),
          const PopupMenuItem(value: 'history', child: Text('Tarix')),
        ],
      ),
    );
  }
}

class _LocationDropdown extends ConsumerWidget {
  const _LocationDropdown({
    required this.value,
    required this.onChanged,
  });

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(allStorageLocationsProvider);
    return locationsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (err, _) => Text('Joylashuvlar xatosi: $err'),
      data: (locations) {
        return DropdownButtonFormField<int?>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Joylashuv',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int?>(
                value: null, child: Text('Tanlanmagan')),
            for (final l in locations)
              DropdownMenuItem<int?>(
                value: l['id'] as int?,
                child: Text(
                  '${l['warehouse_name'] ?? ''} / ${l['code'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _ContainerFormDialog extends ConsumerStatefulWidget {
  const _ContainerFormDialog({required this.batchId});

  final int batchId;

  @override
  ConsumerState<_ContainerFormDialog> createState() =>
      _ContainerFormDialogState();
}

class _ContainerFormDialogState extends ConsumerState<_ContainerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeController = TextEditingController();
  final _quantityController = TextEditingController();
  int? _locationId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _barcodeController.dispose();
    _quantityController.dispose();
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
      final body = <String, dynamic>{
        'container_barcode': _barcodeController.text.trim(),
        'quantity': quantity,
        if (_locationId != null) 'location_id': _locationId,
      };
      await ApiClient().createBatchContainer(auth.token!, widget.batchId, body);
      if (mounted) Navigator.pop(context, 'ok');
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
      title: const Text("Konteyner qo'shish"),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _barcodeController,
                  decoration: const InputDecoration(
                    labelText: 'Shtrix kod',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Shtrix kod majburiy'
                      : null,
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                _LocationDropdown(
                  value: _locationId,
                  onChanged: (v) => setState(() => _locationId = v),
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

class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog({required this.container});

  final Map<String, dynamic> container;

  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _noteController = TextEditingController();
  int? _toLocationId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_toLocationId == null) {
      setState(() => _error = 'Yangi joylashuvni tanlang');
      return;
    }
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient().inventoryTransfer(auth.token!, {
        'batch_container_id': widget.container['id'],
        'to_location_id': _toLocationId,
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context, "Ko'chirish bajarildi");
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
      title: const Text("Ko'chirish (TRANSFER)"),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.container['container_barcode']} | '
                'hozirgi joy: ${widget.container['location_code'] ?? '-'}',
              ),
              const SizedBox(height: 12),
              _LocationDropdown(
                value: _toLocationId,
                onChanged: (v) => setState(() => _toLocationId = v),
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
              : const Text("Ko'chirish"),
        ),
      ],
    );
  }
}

class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({required this.container});

  final Map<String, dynamic> container;

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog> {
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
      final newQuantity = num.parse(_quantityController.text.trim());
      await ApiClient().inventoryAdjustment(auth.token!, {
        'batch_container_id': widget.container['id'],
        'new_quantity': newQuantity,
        'note': _noteController.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context, 'Tuzatish bajarildi');
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
      title: const Text('Tuzatish (ADJUSTMENT)'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.container['container_barcode']} | '
                'hozirgi miqdor: ${widget.container['quantity']}',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Yangi miqdor',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final parsed = num.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed < 0) {
                    return "Miqdor 0 yoki undan katta bo'lishi kerak";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Izoh (majburiy)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Izoh majburiy'
                    : null,
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
              : const Text('Tuzatish'),
        ),
      ],
    );
  }
}