import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/products/product_list_screen.dart';
import 'package:wms_app/features/warehouses/warehouse_detail_screen.dart';

final warehousesProvider = FutureProvider<List<dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getWarehouses(auth.token!)
      : Future.value([]);
});

class WarehouseListScreen extends ConsumerWidget {
  const WarehouseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(warehousesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('Omborlar'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductListScreen()),
            ),
            icon: const Icon(Icons.inventory_2, color: Colors.white),
            label: const Text(
              'Mahsulotlar',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton.icon(
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Chiqish', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: warehousesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Xatolik: $err')),
        data: (warehouses) {
          if (warehouses.isEmpty) {
            return const Center(
              child: Text(
                "Sizga hali ombor biriktirilmagan",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            itemCount: warehouses.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final wh = warehouses[index] as Map<String, dynamic>;
              final name = wh['name'] ?? '';
              final city = wh['city'] ?? '';
              final role = wh['role'] ?? '';
              return ListTile(
                leading: const Icon(Icons.warehouse),
                title: Text(name),
                subtitle: Text(city),
                trailing: Text(
                  role,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WarehouseDetailScreen(warehouse: wh),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}