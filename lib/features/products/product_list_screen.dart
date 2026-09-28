import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/import/bulk_import_screen.dart';
import 'package:wms_app/features/products/product_detail_screen.dart';
import 'package:wms_app/features/products/product_form_screen.dart';

final productCategoryFilterProvider = StateProvider<int?>((ref) => null);
final productSearchProvider = StateProvider<String>((ref) => '');

final productsProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  if (auth.token == null) return Future.value([]);
  final categoryId = ref.watch(productCategoryFilterProvider);
  final search = ref.watch(productSearchProvider);
  return ApiClient().getProducts(auth.token!,
      categoryId: categoryId, search: search);
});

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        ref.read(productSearchProvider.notifier).state = value.trim();
      }
    });
  }

  Future<void> _openForm() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (mounted) {
      ref.invalidate(productsProvider);
    }
  }

  Future<void> _openImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BulkImportScreen()),
    );
    if (mounted) {
      ref.invalidate(productsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final canManage = ref.watch(authProvider).canManageQuality;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mahsulotlar'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Excel import',
              onPressed: _openImport,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Qoshish",
            onPressed: _openForm,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Qidiruv',
                    hintText: "Nomi yoki SKU boyicha",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text("Kategoriya: "),
                    const Expanded(child: _CategoryFilterDropdown()),
                    IconButton(
                      icon: const Icon(Icons.filter_alt_off),
                      tooltip: 'Filtrni tiklash',
                      onPressed: () {
                        ref
                            .read(productCategoryFilterProvider.notifier)
                            .state = null;
                        _searchController.clear();
                        ref.read(productSearchProvider.notifier).state = '';
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Xatolik: $err')),
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Text(
                      'Mahsulotlar topilmadi',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index] as Map<String, dynamic>;
                    final name = product['name'] ?? '';
                    final sku = product['sku'] ?? '';
                    final categoryName = product['category_name'];
                    return ListTile(
                      leading: const Icon(Icons.inventory_2),
                      title: Text('$name ($sku)'),
                      subtitle: categoryName != null
                          ? Text('${product['unit'] ?? ''} | $categoryName')
                          : Text('${product['unit'] ?? ''}'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: product),
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

class _CategoryFilterDropdown extends ConsumerWidget {
  const _CategoryFilterDropdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final current = ref.watch(productCategoryFilterProvider);

    return categoriesAsync.when(
      loading: () => DropdownButton<int?>(
        value: null,
        items: const [],
        onChanged: null,
      ),
      error: (err, _) => Text('Kategoriya xatosi: $err'),
      data: (categories) {
        final items = <DropdownMenuItem<int?>>[
          const DropdownMenuItem<int?>(value: null, child: Text('Barchasi')),
          for (final c in categories)
            DropdownMenuItem<int?>(
              value: c['id'] as int?,
              child: Text(c['name'] as String? ?? ''),
            ),
        ];
        return DropdownButton<int?>(
          value: current,
          isExpanded: true,
          items: items,
          onChanged: (value) =>
              ref.read(productCategoryFilterProvider.notifier).state = value,
        );
      },
    );
  }
}