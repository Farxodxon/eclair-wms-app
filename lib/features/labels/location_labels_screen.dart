import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:wms_app/features/labels/label_pdf_builder.dart';
import 'package:wms_app/features/warehouses/warehouse_detail_screen.dart';
import 'package:wms_app/features/warehouses/warehouse_list_screen.dart';

/// Lets the operator pick storage locations of one warehouse and print their
/// codes as QR stickers on a plain A4 PDF sheet.
class LocationLabelsScreen extends ConsumerStatefulWidget {
  const LocationLabelsScreen({super.key});

  @override
  ConsumerState<LocationLabelsScreen> createState() =>
      _LocationLabelsScreenState();
}

class _LocationLabelsScreenState extends ConsumerState<LocationLabelsScreen> {
  final Set<int> _selected = <int>{};
  int? _warehouseId;
  String _warehouseName = '';
  bool _printing = false;

  /// Reads [field] from the list entry whose `id` equals [id].
  static String _fieldOf(List<dynamic> list, int? id, String field) {
    for (final entry in list) {
      if (entry is Map<String, dynamic> && entry['id'] == id) {
        return (entry[field] ?? '').toString();
      }
    }
    return '';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  void _selectAll(List<Map<String, dynamic>> locations) {
    setState(() {
      _selected
        ..clear()
        ..addAll(locations.map((l) => l['id'] as int));
    });
  }

  void _selectNone() {
    setState(_selected.clear);
  }

  Future<void> _print(List<Map<String, dynamic>> locations) async {
    if (_selected.isEmpty) {
      _showMessage('Avval joylashuvlarni belgilang', isError: true);
      return;
    }
    final items = <LabelItem>[];
    for (final location in locations) {
      if (!_selected.contains(location['id'])) continue;
      final code = (location['code'] ?? '').toString();
      if (code.isEmpty) continue;
      items.add(LabelItem(code: code, caption: '$code / $_warehouseName'));
    }
    if (items.isEmpty) {
      _showMessage('Kodlari bo\'sh joylashuvlar topilmadi', isError: true);
      return;
    }

    setState(() => _printing = true);
    try {
      final bytes = await buildLabelSheet(items);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Joylashuv yorliqlari',
      );
    } catch (e) {
      _showMessage('Chop etishda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(warehousesProvider);
    final locationsAsync = _warehouseId == null
        ? const AsyncValue<List<dynamic>>.data(<dynamic>[])
        : ref.watch(storageLocationsProvider(_warehouseId!));

    return Scaffold(
      appBar: AppBar(title: const Text('Joylashuv yorliqlari')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: warehousesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Omborlar xatosi: $err'),
              data: (warehouses) {
                return DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ombor',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final w in warehouses)
                      DropdownMenuItem<int>(
                        value: w['id'] as int?,
                        child: Text(w['name'] as String? ?? ''),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _warehouseId = value;
                      _warehouseName = _fieldOf(warehouses, value, 'name');
                      _selected.clear();
                    });
                  },
                );
              },
            ),
          ),
          if (_warehouseId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => locationsAsync.maybeWhen(
                        data: (list) =>
                            _selectAll(list.cast<Map<String, dynamic>>()),
                        orElse: () {},
                      ),
                      icon: const Icon(Icons.done_all),
                      label: const Text('Hammasini belgilash'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectNone,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Hech birini belgilamaslik'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _warehouseId == null
                ? const Center(
                    child: Text(
                      'Omborni tanlang',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : locationsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Xatolik: $err')),
                    data: (data) {
                      final locations =
                          data.cast<Map<String, dynamic>>();
                      if (locations.isEmpty) {
                        return const Center(
                          child: Text(
                            'Joylashuvlar topilmadi',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: locations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final location = locations[index];
                          final id = location['id'] as int;
                          final zoneName = location['zone_name'];
                          return CheckboxListTile(
                            value: _selected.contains(id),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                            title: Text('${location['code'] ?? ''}'),
                            subtitle: Text(
                              zoneName is String && zoneName.isNotEmpty
                                  ? zoneName
                                  : 'Zonasiz',
                            ),
                            secondary: const Icon(Icons.qr_code_2),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _printing ||
                    _warehouseId == null ||
                    locationsAsync.valueOrNull == null
                ? null
                : () => _print(
                      locationsAsync.valueOrNull!.cast<Map<String, dynamic>>(),
                    ),
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            label: Text(
              _printing
                  ? 'Tayyorlanmoqda...'
                  : 'Tanlanganlarni chop etish (${_selected.length})',
            ),
          ),
        ),
      ),
    );
  }
}
