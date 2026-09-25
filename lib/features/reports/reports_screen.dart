import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/warehouses/warehouse_list_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int? _stockWarehouseId;
  int? _transactionsWarehouseId;
  DateTimeRange? _dateRange;
  bool _stockLoading = false;
  bool _transactionsLoading = false;

  String _isoDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-$month-$day';
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      initialDateRange: _dateRange,
      helpText: 'Sana oralig\'ini tanlang',
    );
    if (range != null && mounted) {
      setState(() => _dateRange = range);
    }
  }

  Future<void> _downloadStock() async {
    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null) return;
    setState(() => _stockLoading = true);
    try {
      final bytes = await ApiClient().getStockReportBytes(
        token,
        warehouseId: _stockWarehouseId,
      );
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        throw ApiException("Downloads papkasi topilmadi");
      }
      final file = File('${dir.path}/wms-qoldiq-${_isoDate(DateTime.now())}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      _showMessage('Fayl saqlandi: ${file.path}');
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage("Faylni saqlashda xatolik: $e", isError: true);
    } finally {
      if (mounted) setState(() => _stockLoading = false);
    }
  }

  Future<void> _downloadTransactions() async {
    final range = _dateRange;
    if (range == null) {
      _showMessage("Avval sana oralig'ini tanlang");
      return;
    }
    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null) return;
    setState(() => _transactionsLoading = true);
    try {
      final bytes = await ApiClient().getTransactionsReportBytes(
        token,
        from: range.start,
        to: range.end,
        warehouseId: _transactionsWarehouseId,
      );
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        throw ApiException("Downloads papkasi topilmadi");
      }
      final file = File(
        '${dir.path}/wms-harakatlar-${_isoDate(range.start)}-${_isoDate(range.end)}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      _showMessage('Fayl saqlandi: ${file.path}');
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (e) {
      _showMessage("Faylni saqlashda xatolik: $e", isError: true);
    } finally {
      if (mounted) setState(() => _transactionsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: const Text('Hisobotlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ReportCard(
            icon: Icons.inventory,
            title: 'Qoldiq hisoboti',
            children: [
              _WarehouseDropdown(
                value: _stockWarehouseId,
                onChanged: (id) => setState(() => _stockWarehouseId = id),
              ),
              const SizedBox(height: 16),
              _DownloadButton(
                loading: _stockLoading,
                label: _stockLoading ? "Yuklanmoqda..." : 'Yuklab olish',
                onPressed: _downloadStock,
              ),
            ],
          ),
          _ReportCard(
            icon: Icons.swap_horiz,
            title: 'Harakatlar hisoboti',
            children: [
              InkWell(
                onTap: _pickDateRange,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: "Sana oralig'i",
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.date_range),
                  ),
                  child: Text(
                    _dateRange == null
                        ? 'Tanlanmagan'
                        : '${_isoDate(_dateRange!.start)} - ${_isoDate(_dateRange!.end)}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _WarehouseDropdown(
                value: _transactionsWarehouseId,
                onChanged: (id) =>
                    setState(() => _transactionsWarehouseId = id),
              ),
              const SizedBox(height: 16),
              _DownloadButton(
                loading: _transactionsLoading,
                label:
                    _transactionsLoading ? "Yuklanmoqda..." : 'Yuklab olish',
                onPressed: _downloadTransactions,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _WarehouseDropdown extends ConsumerWidget {
  const _WarehouseDropdown({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(warehousesProvider);

    return warehousesAsync.when(
      loading: () => DropdownButton<int?>(
        value: null,
        items: const [],
        onChanged: null,
      ),
      error: (err, _) => Text('Omborlar xatosi: $err'),
      data: (warehouses) {
        final items = <DropdownMenuItem<int?>>[
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('Barcha omborlar'),
          ),
          for (final w in warehouses)
            DropdownMenuItem<int?>(
              value: w['id'] as int?,
              child: Text(w['name'] as String? ?? ''),
            ),
        ];
        return DropdownButton<int?>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.loading,
    required this.label,
    required this.onPressed,
  });

  final bool loading;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download),
      label: Text(label),
    );
  }
}