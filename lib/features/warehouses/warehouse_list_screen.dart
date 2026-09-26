import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/alerts/expiring_batches_screen.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/labels/labels_home_screen.dart';
import 'package:wms_app/features/products/product_list_screen.dart';
import 'package:wms_app/features/quality/quality_pending_screen.dart';
import 'package:wms_app/features/reports/reports_screen.dart';
import 'package:wms_app/features/scanner/scan_screen.dart';
import 'package:wms_app/features/warehouses/warehouse_detail_screen.dart';

final warehousesProvider = FutureProvider<List<dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getWarehouses(auth.token!)
      : Future.value([]);
});

final alertsSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getAlertsSummary(auth.token!)
      : Future.value(const <String, dynamic>{});
});

class WarehouseListScreen extends ConsumerWidget {
  const WarehouseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(warehousesProvider);
    final summaryAsync = ref.watch(alertsSummaryProvider);
    final summary = summaryAsync.valueOrNull;
    final badgeCount =
        (((summary?['expired_count'] as num?) ?? 0) +
            ((summary?['critical_count'] as num?) ?? 0))
            .toInt();
    final pendingAsync = ref.watch(qualityPendingProvider);
    final pendingCount = pendingAsync.valueOrNull?.length ?? 0;
    final canManageReports = ref.watch(authProvider).canManageQuality;

    Future<void> openAlerts() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ExpiringBatchesScreen()),
      );
      if (context.mounted) {
        ref.invalidate(alertsSummaryProvider);
      }
    }

    Future<void> openQuality() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QualityPendingScreen()),
      );
      if (context.mounted) {
        ref.invalidate(qualityPendingProvider);
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('Omborlar'),
        actions: [
          IconButton(
            tooltip: 'Ogohlantirishlar',
            onPressed: openAlerts,
            icon: badgeCount > 0
                ? Badge(
                    label: Text('$badgeCount'),
                    child: const Icon(
                      Icons.notifications,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.notifications, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Sifat tekshiruvi',
            onPressed: openQuality,
            icon: pendingCount > 0
                ? Badge(
                    label: Text('$pendingCount'),
                    child: const Icon(
                      Icons.verified,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified, color: Colors.white),
          ),
          if (canManageReports)
            IconButton(
              tooltip: 'Hisobotlar',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              ),
              icon: const Icon(Icons.assessment, color: Colors.white),
            ),
          IconButton(
            tooltip: 'Skaner',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScanScreen()),
            ),
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Yorliqlar',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LabelsHomeScreen()),
            ),
            icon: const Icon(Icons.sell_outlined, color: Colors.white),
          ),
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