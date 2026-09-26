import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/labels/label_pdf_builder.dart';
import 'package:wms_app/features/products/batch_containers_screen.dart';
import 'package:wms_app/features/products/product_detail_screen.dart';

/// Products for the label picker. Intentionally unfiltered: unlike the
/// product list screen this must not inherit its search / category state.
final labelProductsProvider = FutureProvider<List<dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getProducts(auth.token!)
      : Future.value(<dynamic>[]);
});

/// Prints the barcodes of the containers of one batch as QR stickers.
class ContainerLabelsScreen extends ConsumerStatefulWidget {
  const ContainerLabelsScreen({super.key});

  @override
  ConsumerState<ContainerLabelsScreen> createState() =>
      _ContainerLabelsScreenState();
}

class _ContainerLabelsScreenState extends ConsumerState<ContainerLabelsScreen> {
  final Set<int> _selected = <int>{};
  int? _productId;
  int? _batchId;
  String _productName = '';
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

  void _selectAll(List<Map<String, dynamic>> containers) {
    setState(() {
      _selected
        ..clear()
        ..addAll(containers.map((c) => c['id'] as int));
    });
  }

  void _selectNone() {
    setState(_selected.clear);
  }

  Future<void> _print(List<Map<String, dynamic>> containers) async {
    if (_selected.isEmpty) {
      _showMessage('Avval konteynerlarni belgilang', isError: true);
      return;
    }
    final items = <LabelItem>[];
    for (final container in containers) {
      if (!_selected.contains(container['id'])) continue;
      final barcode = (container['container_barcode'] ?? '').toString();
      if (barcode.isEmpty) continue;
      items.add(LabelItem(code: barcode, caption: '$barcode / $_productName'));
    }
    if (items.isEmpty) {
      _showMessage('Shtrix kodlari bo\'sh konteynerlar topilmadi',
          isError: true);
      return;
    }

    setState(() => _printing = true);
    try {
      final bytes = await buildLabelSheet(items);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Konteyner yorliqlari',
      );
    } catch (e) {
      _showMessage('Chop etishda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(labelProductsProvider);
    final batchesAsync = _productId == null
        ? const AsyncValue<List<dynamic>>.data(<dynamic>[])
        : ref.watch(productBatchesProvider(_productId!));
    final containersAsync = _batchId == null
        ? const AsyncValue<List<dynamic>>.data(<dynamic>[])
        : ref.watch(batchContainersProvider(_batchId!));

    return Scaffold(
      appBar: AppBar(title: const Text('Konteyner yorliqlari')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                productsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (err, _) => Text('Mahsulotlar xatosi: $err'),
                  data: (products) {
                    return DropdownButtonFormField<int>(
                      initialValue: _productId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Mahsulot',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in products)
                          DropdownMenuItem<int>(
                            value: p['id'] as int?,
                            child: Text(
                              '${p['name'] ?? ''} (${p['sku'] ?? ''})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _productId = value;
                          _productName = _fieldOf(products, value, 'name');
                          _batchId = null;
                          _selected.clear();
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
                batchesAsync.maybeWhen(
                  data: (batches) {
                    return DropdownButtonFormField<int>(
                      initialValue: _batchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Partiya',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final b in batches)
                          DropdownMenuItem<int>(
                            value: b['id'] as int?,
                            child: Text(
                              'Lot: ${b['lot_number'] ?? ''} | '
                              'muddat: ${b['expiry_date'] ?? '-'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _productId == null
                          ? null
                          : (value) {
                              setState(() {
                                _batchId = value;
                                _selected.clear();
                              });
                            },
                    );
                  },
                  orElse: () => DropdownButtonFormField<int>(
                        initialValue: null,
                        decoration: const InputDecoration(
                          labelText: 'Partiya',
                          border: OutlineInputBorder(),
                        ),
                        items: const [],
                        onChanged: null,
                      ),
                ),
              ],
            ),
          ),
          if (_batchId != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => containersAsync.maybeWhen(
                        data: (list) => _selectAll(list.cast<Map<String, dynamic>>()),
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
          Expanded(child: _buildContainerList(containersAsync)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _printing ||
                    _batchId == null ||
                    containersAsync.valueOrNull == null
                ? null
                : () => _print(
                      containersAsync.valueOrNull!.cast<Map<String, dynamic>>(),
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

  Widget _buildContainerList(AsyncValue<List<dynamic>> containersAsync) {
    if (_productId == null) {
      return const _Hint('Mahsulotni tanlang');
    }
    if (_batchId == null) {
      return const _Hint('Partiyani tanlang');
    }
    return containersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Xatolik: $err')),
      data: (data) {
        final containers = data.cast<Map<String, dynamic>>();
        if (containers.isEmpty) {
          return const _Hint('Konteynerlar topilmadi');
        }
        return ListView.separated(
          itemCount: containers.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final container = containers[index];
            final id = container['id'] as int;
            return CheckboxListTile(
              value: _selected.contains(id),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(id);
                } else {
                  _selected.remove(id);
                }
              }),
              title: Text('${container['container_barcode'] ?? ''}'),
              subtitle: Text(
                'Miqdor: ${container['quantity'] ?? 0} | '
                'Joy: ${container['location_code'] ?? '-'}',
              ),
              secondary: const Icon(Icons.qr_code_2),
            );
          },
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, color: Colors.grey),
      ),
    );
  }
}
