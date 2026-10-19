import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/labels/label_pdf_builder.dart';
import 'package:wms_app/features/products/transaction_history_screen.dart';
import 'package:wms_app/core/container_types.dart';

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

  Future<void> _showPrintDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> created,
  ) async {
    final barcode = (created['container_barcode'] ?? '').toString();
    final qty = (created['quantity'] as num?) ?? 0;
    final unitWeight = created['unit_weight_kg'] as num?;
    final copies = (unitWeight != null && unitWeight > 0)
        ? (qty / unitWeight).round().clamp(1, 1000)
        : 1;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kirim saqlandi'),
        content: Text(
          'QR kod: $barcode\n'
          '$copies dona x ${unitWeight ?? '-'} kg = $qty kg',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Yopish'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _printLabels(context, ref, barcode, copies);
            },
            icon: const Icon(Icons.print),
            label: Text('Chop etish ($copies ta QR)'),
          ),
        ],
      ),
    );
  }

  Future<void> _printLabels(
    BuildContext context,
    WidgetRef ref,
    String barcode,
    int copies,
  ) async {
    final auth = ref.read(authProvider);
    if (auth.token == null) return;
    try {
      final product = await ApiClient().getProduct(auth.token!, productId);
      final caption = '$barcode / ${product['name'] ?? ''}';
      final items = List.generate(
        copies,
        (_) => LabelItem(code: barcode, caption: caption),
      );
      final bytes = await buildLabelSheet(items);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Konteyner yorliqlari',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chop etishda xatolik: $e')),
        );
      }
    }
  }

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
          final created = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (_) => _ContainerFormDialog(
              batchId: batchId,
              productId: productId,
            ),
          );
          if (created != null) {
            ref.invalidate(batchContainersProvider(batchId));
            if (context.mounted) {
              await _showPrintDialog(context, ref, created);
            }
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

/// Formats [value] without a trailing `.0` so `500` is shown instead of
/// `500.0`.
String _formatKg(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
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

  /// `20 dona x 25 kg = 500 kg` for containers created with a unit weight,
  /// plain kilograms for legacy containers.
  String quantityLabel() {
    final quantity = container['quantity'] as num? ?? 0;
    final unitWeight = container['unit_weight_kg'] as num?;
    if (unitWeight != null && unitWeight > 0) {
      final units = quantity / unitWeight;
      return 'Miqdor: ${_formatKg(units)} dona x ${_formatKg(unitWeight)} kg '
          '= ${_formatKg(quantity)} kg';
    }
    return 'Miqdor: ${_formatKg(quantity)} kg';
  }

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
        '${quantityLabel()} | '
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
  const _ContainerFormDialog({
    required this.batchId,
    required this.productId,
  });

  final int batchId;
  final int productId;

  @override
  ConsumerState<_ContainerFormDialog> createState() =>
      _ContainerFormDialogState();
}

class _ContainerFormDialogState extends ConsumerState<_ContainerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeController = TextEditingController();
  final _unitCountController = TextEditingController();
  final _unitWeightController = TextEditingController();
  int? _locationId;
  String? _error;
  bool _saving = false;
  bool _loadingDefaults = true;
  String _containerType = '';
  final _containerTypeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _unitCountController.addListener(_refreshTotal);
    _unitWeightController.addListener(_refreshTotal);
    _loadDefaults();
  }

  @override
  void dispose() {
    _unitCountController.removeListener(_refreshTotal);
    _unitWeightController.removeListener(_refreshTotal);
    _barcodeController.dispose();
    _unitCountController.dispose();
    _unitWeightController.dispose();
    _containerTypeController.dispose();
    super.dispose();
  }

  void _refreshTotal() {
    if (mounted) setState(() {});
  }

  /// Prefills the container type and single unit weight of the product.
  Future<void> _loadDefaults() async {
    final auth = ref.read(authProvider);
    if (auth.token == null) {
      if (mounted) setState(() => _loadingDefaults = false);
      return;
    }
    try {
      final product = await ApiClient().getProduct(
        auth.token!,
        widget.productId,
      );
      final type = (product['default_container_type'] ?? '').toString();
      final weight = product['default_unit_weight_kg'] as num?;
      if (!mounted) return;
      _unitWeightController.text = weight != null ? _formatKg(weight) : '';
      _containerTypeController.text = type;
      setState(() {
        _containerType = type;
        _loadingDefaults = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDefaults = false);
    }
  }

  double get _totalKg {
    final count = num.tryParse(_unitCountController.text.trim()) ?? 0;
    final weight = num.tryParse(_unitWeightController.text.trim()) ?? 0;
    return (count * weight).toDouble();
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
        if (_barcodeController.text.trim().isNotEmpty)
          'container_barcode': _barcodeController.text.trim(),
        'unit_count': num.parse(_unitCountController.text.trim()),
        'unit_weight_kg': num.parse(_unitWeightController.text.trim()),
        if (_locationId != null) 'location_id': _locationId,
      };
      if (_containerTypeController.text.trim().isNotEmpty) {
        body['container_type'] = _containerTypeController.text.trim();
      }
      final created = await ApiClient()
          .createBatchContainer(auth.token!, widget.batchId, body);
      try {
        final product = await ApiClient().getProduct(auth.token!, widget.productId);
        final needsUpdate = (product['default_container_type'] == null ||
                (product['default_container_type'] as String).isEmpty ||
                product['default_unit_weight_kg'] == null) &&
            (_containerTypeController.text.trim().isNotEmpty ||
                _unitWeightController.text.trim().isNotEmpty);
        if (needsUpdate) {
          final updateBody = <String, dynamic>{};
          if (product['default_container_type'] == null ||
              (product['default_container_type'] as String).isEmpty) {
            if (_containerTypeController.text.trim().isNotEmpty) {
              updateBody['default_container_type'] =
                  _containerTypeController.text.trim();
            }
          }
          if (product['default_unit_weight_kg'] == null) {
            final w = num.tryParse(_unitWeightController.text.trim());
            if (w != null) updateBody['default_unit_weight_kg'] = w;
          }
          if (updateBody.isNotEmpty) {
            await ApiClient().updateProduct(
              auth.token!,
              widget.productId,
              updateBody,
            );
          }
        }
      } catch (_) {
        // ignore
      }
      if (mounted) Navigator.pop(context, created);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Idish soni va og\'irlikni son formatida kiriting';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Konteyner qo'shish"),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingDefaults)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                DropdownButtonFormField<String>(
                  value: _containerTypeController.text.isEmpty
                      ? null
                      : _containerTypeController.text,
                  decoration: const InputDecoration(
                    labelText: 'Idish turi (ixtiyoriy)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Tanlanmagan'),
                    ),
                    for (final t in containerTypeOptions(
                      _containerTypeController.text,
                    ))
                      DropdownMenuItem<String>(
                        value: t,
                        child: Text(t),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _containerTypeController.text = value ?? '';
                      _containerType = _containerTypeController.text;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _barcodeController,
                  decoration: const InputDecoration(
                    labelText: "QR kod (bo'sh qoldirilsa avtomatik yaratiladi)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _unitCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Idish soni',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final parsed = int.tryParse(v?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return "Idish soni 0 dan katta bo'lishi kerak";
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unitWeightController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '1 idish og\'irligi (kg)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final parsed =
                              num.tryParse(v?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return "Og'irlik 0 dan katta bo'lishi kerak";
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Jami: ${_formatKg(_totalKg)} kg',
                  style: const TextStyle(fontWeight: FontWeight.bold),
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
          onPressed: _saving || _loadingDefaults ? null : _save,
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
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _error;
  bool _saving = false;

  /// Single unit weight in kg, or null for legacy containers that are
  /// tracked in kilograms only.
  double? get _unitWeight {
    final raw = widget.container['unit_weight_kg'];
    if (raw is num && raw > 0) return raw.toDouble();
    return null;
  }

  double get _availableKg =>
      (widget.container['quantity'] as num?)?.toDouble() ?? 0;

  int get _availableUnits {
    final weight = _unitWeight;
    if (weight == null) return 0;
    return (_availableKg / weight).round();
  }

  /// The backend always works in kilograms, so unit input is converted here.
  double get _outKg {
    final entered = num.tryParse(_amountController.text.trim()) ?? 0;
    final weight = _unitWeight;
    return (weight == null ? entered : entered * weight).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_refreshTotal);
  }

  @override
  void dispose() {
    _amountController.removeListener(_refreshTotal);
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _refreshTotal() {
    if (mounted) setState(() {});
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
      final result = await ApiClient().inventoryOut(auth.token!, {
        'batch_container_id': widget.container['id'],
        'quantity': _outKg,
        if (_noteController.text.trim().isNotEmpty)
          'note': _noteController.text.trim(),
      });
      final remaining = result['remaining_quantity'] ?? result['quantity'];
      final remainingKg = remaining is num ? remaining.toDouble() : 0.0;
      final weight = _unitWeight;
      if (mounted) {
        final suffix = weight == null
            ? '${_formatKg(remainingKg)} kg'
            : '${_formatKg(remainingKg)} kg '
                  '(${(remainingKg / weight).round()} dona)';
        Navigator.pop(context, 'Chiqarish bajarildi, qoldi: $suffix');
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
    final weight = _unitWeight;
    return AlertDialog(
      title: const Text('Chiqarish (OUT)'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.container['container_barcode']} | '
                'mavjud: ${weight == null ? '${_formatKg(_availableKg)} kg' : '$_availableUnits dona (${_formatKg(_availableKg)} kg)'}',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: weight == null ? 'Miqdor (kg)' : 'Idish soni',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final parsed = num.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return "0 dan katta bo'lishi kerak";
                  }
                  if (weight == null) {
                    if (parsed > _availableKg) {
                      return 'Mavjud: ${_formatKg(_availableKg)} kg';
                    }
                    return null;
                  }
                  if (parsed > _availableUnits) {
                    return 'Mavjud: $_availableUnits dona';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Jami chiqariladi: ${_formatKg(_outKg)} kg',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (weight != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '1 idish = ${_formatKg(weight)} kg. Chiqarish kg '
                    'boshqariladi, idish soni orqali kiritiladi.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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