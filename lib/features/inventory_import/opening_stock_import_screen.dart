import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';
import 'package:wms_app/features/inventory_import/opening_stock_parser.dart';
import 'package:wms_app/features/labels/label_pdf_builder.dart';

final openingStockWarehousesProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) {
      final auth = ref.watch(authProvider);
      return auth.token != null
          ? ApiClient().getWarehouses(auth.token!)
          : Future.value(const <dynamic>[]);
    });

final openingStockCategoriesProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) {
      final auth = ref.watch(authProvider);
      return auth.token != null
          ? ApiClient().getCategories(auth.token!)
          : Future.value(const <dynamic>[]);
    });

class OpeningStockImportScreen extends ConsumerStatefulWidget {
  const OpeningStockImportScreen({super.key});

  @override
  ConsumerState<OpeningStockImportScreen> createState() =>
      _OpeningStockImportScreenState();
}

class _OpeningStockImportScreenState
    extends ConsumerState<OpeningStockImportScreen> {
  final ApiClient _api = ApiClient();

  String? _fileName;
  OpeningStockParseResult? _parsed;
  String? _parseError;
  int? _warehouseId;
  int? _categoryId;

  Map<String, dynamic>? _dryRun;
  bool _dryRunOk = false;
  Map<String, dynamic>? _result;
  List<Map<String, dynamic>> _containers = [];
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(openingStockWarehousesProvider);
    final categoriesAsync = ref.watch(openingStockCategoriesProvider);
    final parsed = _parsed;

    return Scaffold(
      appBar: AppBar(title: const Text("Boshlang'ich qoldiq importi")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOptions(warehousesAsync, categoriesAsync),
          const SizedBox(height: 12),
          _buildFileSection(),
          if (parsed != null) ...[
            const SizedBox(height: 12),
            _buildPreview(parsed),
          ],
          const SizedBox(height: 12),
          _buildActions(),
          if (_dryRun != null) ...[
            const SizedBox(height: 12),
            _buildDryRunResult(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            _buildImportResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildOptions(
    AsyncValue<List<dynamic>> warehousesAsync,
    AsyncValue<List<dynamic>> categoriesAsync,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import sozlamalari',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            warehousesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Omborlar xatosi: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              data: (warehouses) => DropdownButtonFormField<int?>(
                initialValue: _warehouseId,
                decoration: const InputDecoration(
                  labelText: 'Ombor (joylashuv uchun)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tanlanmagan'),
                  ),
                  for (final item in warehouses)
                    DropdownMenuItem<int?>(
                      value: _asInt(_asMap(item)['id']),
                      child: Text((_asMap(item)['name'] ?? '').toString()),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          _warehouseId = value;
                          _resetAfterChange();
                        });
                      },
              ),
            ),
            const SizedBox(height: 12),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Kategoriyalar xatosi: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              data: (categories) => DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Standart kategoriya',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tanlanmagan'),
                  ),
                  for (final item in categories)
                    DropdownMenuItem<int?>(
                      value: _asInt(_asMap(item)['id']),
                      child: Text((_asMap(item)['name'] ?? '').toString()),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          _categoryId = value;
                          _resetAfterChange();
                        });
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Excel fayl',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Excel faylni tanlash'),
            ),
            const SizedBox(height: 4),
            const Text(
              "Faqat .xlsx. 'Qoldiq' varag'i olinadi (bo'lmasa birinchi varaq).",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text('Tanlangan fayl: $_fileName'),
            ],
            if (_parseError != null) ...[
              const SizedBox(height: 8),
              Text(
                _parseError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(OpeningStockParseResult parsed) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ko\'rib chiqish',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Varaq: ${parsed.sheetName}'),
            Text('Qatorlar: ${parsed.rows.length}'),
            Text('Jami (ma\'lum): ${_knownTotal.toStringAsFixed(2)} kg'),
            if (parsed.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  "Faylda ma'lumot qatori yo'q",
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            const SizedBox(height: 8),
            if (parsed.rows.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('SKU')),
                    DataColumn(label: Text('Nomi')),
                    DataColumn(label: Text('Idish')),
                    DataColumn(label: Text('1 idish kg')),
                    DataColumn(label: Text('Partiya')),
                    DataColumn(label: Text('Muddat')),
                    DataColumn(label: Text('Joylashuv')),
                  ],
                  rows: [
                    for (final row in parsed.rows.take(20))
                      DataRow(
                        cells: [
                          DataCell(Text('${row.row}')),
                          DataCell(Text(row.sku)),
                          DataCell(Text(row.name ?? '')),
                          DataCell(Text(row.unitCount?.toString() ?? '')),
                          DataCell(Text(row.unitWeightKg?.toString() ?? '')),
                          DataCell(Text(row.lotNumber ?? '')),
                          DataCell(Text(row.expiryDate ?? '')),
                          DataCell(Text(row.locationCode ?? '')),
                        ],
                      ),
                  ],
                ),
              ),
            if (parsed.rows.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('... yana ${parsed.rows.length - 20} qator'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final parsed = _parsed;
    final canCheck = !_busy && parsed != null && parsed.rows.isNotEmpty;
    final canImport = !_busy && _dryRunOk && _result == null && parsed != null;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: canCheck ? _runDryRun : null,
          icon: const Icon(Icons.fact_check),
          label: const Text('Tekshirish'),
        ),
        FilledButton.icon(
          onPressed: canImport ? _confirmImport : null,
          icon: const Icon(Icons.download_done),
          label: Text(_result == null ? 'Import qilish' : 'Import qilindi'),
        ),
        if (_result != null && _containers.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _busy ? null : _printAll,
            icon: const Icon(Icons.print),
            label: const Text('Hammasini chop etish'),
          ),
      ],
    );
  }

  Widget _buildDryRunResult() {
    final response = _dryRun!;
    final errors = (response['errors'] as List?) ?? const [];
    final summary = _summary;

    if (_dryRunOk) {
      return Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tekshiruv muvaffaqiyatli',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              if (summary != null) ...[
                const SizedBox(height: 8),
                Text('Yangi mahsulotlar: ${summary['new_products'] ?? 0}'),
                Text('Yangi partiyalar: ${summary['created_batches'] ?? 0}'),
                Text('Konteynerlar: ${summary['created_containers'] ?? 0}'),
                Text('Jami: ${summary['total_kg'] ?? 0} kg'),
                Text(
                  'Faqat mahsulot kartasi: ${summary['products_only'] ?? 0}',
                ),
                Text("Qoldiqsiz o'tkazildi: ${summary['skipped_no_qty'] ?? 0}"),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tekshiruvda xatolar bor (${errors.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final error in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_asMap(error)['row'] ?? '?'}-qator: '
                  '${_asMap(error)['message'] ?? ''}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportResult() {
    final result = _result!;
    final summary = result['summary'] is Map
        ? Map<String, dynamic>.from(result['summary'] as Map)
        : const <String, dynamic>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import yakunlandi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Yangi mahsulotlar: ${summary['new_products'] ?? 0}'),
            Text('Partiyalar: ${summary['created_batches'] ?? 0}'),
            Text('Konteynerlar: ${summary['created_containers'] ?? 0}'),
            Text('Jami: ${summary['total_kg'] ?? 0} kg'),
            if (_containers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text("Konteynerlar ro'yxati bo'sh"),
              ),
            const SizedBox(height: 8),
            for (final container in _containers)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    (container['container_barcode'] ?? '').toString(),
                  ),
                  subtitle: Text(_containerSubtitle(container)),
                  trailing: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _printContainer(container),
                    icon: const Icon(Icons.print),
                    label: const Text('Chop etish'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _parseError = null);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Excel faylni tanlang',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() {
        _fileName = picked.name;
        _parsed = null;
        _parseError = "Faylni o'qib bo'lmadi";
        _resetAfterChange();
      });
      return;
    }

    try {
      final parsed = parseOpeningStockSheet(bytes);
      setState(() {
        _fileName = picked.name;
        _parsed = parsed;
        _parseError = null;
        _resetAfterChange();
      });
    } on OpeningStockParseException catch (e) {
      setState(() {
        _fileName = picked.name;
        _parsed = null;
        _parseError = e.message;
        _resetAfterChange();
      });
    } catch (e) {
      setState(() {
        _fileName = picked.name;
        _parsed = null;
        _parseError = "Faylni o'qib bo'lmadi: $e";
        _resetAfterChange();
      });
    }
  }

  void _resetAfterChange() {
    _dryRun = null;
    _dryRunOk = false;
    _result = null;
    _containers = [];
  }

  Future<void> _runDryRun() async {
    final token = ref.read(authProvider).token;
    final parsed = _parsed;
    if (token == null || parsed == null) return;

    setState(() {
      _busy = true;
      _dryRun = null;
      _dryRunOk = false;
      _result = null;
      _containers = [];
    });

    try {
      final response = await _api.importOpeningStock(
        token,
        _requestBody(parsed),
        dryRun: true,
      );
      if (!mounted) return;
      setState(() {
        _dryRun = response;
        _dryRunOk = response['ok'] == true;
      });
    } on ApiException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Tekshirishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmImport() async {
    final summary = _summary;
    if (summary == null) return;
    final containers = _asInt(summary['created_containers']) ?? 0;
    final totalKg = _toNum(summary['total_kg']) ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importni tasdiqlang'),
        content: Text(
          '$containers ta konteyner, $totalKg kg yoziladi.\n\n'
          "Diqqat: qayta import qilinsa qoldiq ikki baravar bo'ladi.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ha, import qilish'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _runImport();
  }

  Future<void> _runImport() async {
    final token = ref.read(authProvider).token;
    final parsed = _parsed;
    if (token == null || parsed == null) return;

    setState(() {
      _busy = true;
      _result = null;
      _containers = [];
    });

    try {
      final response = await _api.importOpeningStock(
        token,
        _requestBody(parsed),
      );
      if (!mounted) return;
      if (response['error'] == 'validation_failed') {
        setState(() {
          _dryRun = response;
          _dryRunOk = false;
        });
        _showSnack("Import to'xtatildi: xatolar bor");
        return;
      }
      final rawContainers = (response['containers'] as List?) ?? const [];
      setState(() {
        _result = response;
        _containers = rawContainers
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _dryRun = null;
        _dryRunOk = false;
      });
    } on ApiException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Importda xatolik: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _requestBody(OpeningStockParseResult parsed) {
    final body = <String, dynamic>{
      'rows': parsed.rows.map((row) => row.toJson()).toList(),
    };
    if (_warehouseId != null) body['warehouse_id'] = _warehouseId;
    if (_categoryId != null) body['default_category_id'] = _categoryId;
    return body;
  }

  Future<void> _printContainer(Map<String, dynamic> container) async {
    final barcode = (container['container_barcode'] ?? '').toString();
    final caption = '$barcode / ${container['product_name'] ?? ''}';
    final copies = _copiesFor(container);
    final items = List.generate(
      copies,
      (_) => LabelItem(code: barcode, caption: caption),
    );
    await _printItems(items, 'Konteyner yorlig\'i');
  }

  Future<void> _printItems(List<LabelItem> items, String name) async {
    if (items.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildLabelSheet(items);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    } catch (e) {
      _showSnack('Chop etishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printAll() async {
    final items = <LabelItem>[];
    for (final container in _containers) {
      final barcode = (container['container_barcode'] ?? '').toString();
      final caption = '$barcode / ${container['product_name'] ?? ''}';
      final copies = _copiesFor(container);
      items.addAll(
        List.generate(
          copies,
          (_) => LabelItem(code: barcode, caption: caption),
        ),
      );
    }
    if (items.isEmpty) return;

    const chunkSize = 300;
    final chunks = <List<LabelItem>>[];
    for (var start = 0; start < items.length; start += chunkSize) {
      final end = start + chunkSize < items.length
          ? start + chunkSize
          : items.length;
      chunks.add(items.sublist(start, end));
    }

    setState(() => _busy = true);
    try {
      for (var i = 0; i < chunks.length; i++) {
        final bytes = await buildLabelSheet(chunks[i]);
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'Konteyner yorliqlari (${i + 1}/${chunks.length})',
        );
        if (!mounted) break;
        if (i < chunks.length - 1) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Chop etish'),
              content: Text('Keyingisi (${i + 2}/${chunks.length})'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Bekor qilish'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Davom etish'),
                ),
              ],
            ),
          );
          if (proceed != true) break;
        }
      }
    } catch (e) {
      _showSnack('Chop etishda xatolik: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _copiesFor(Map<String, dynamic> container) {
    final count = _toNum(container['unit_count']) ?? 0;
    final copies = count.round();
    if (copies < 1) return 1;
    if (copies > 1000) return 1000;
    return copies;
  }

  String _containerSubtitle(Map<String, dynamic> container) {
    final sku = container['sku'] ?? '';
    final name = container['product_name'] ?? '';
    final unitCount = container['unit_count'] ?? '';
    final unitWeight = container['unit_weight_kg'] ?? '';
    final quantity = container['quantity'] ?? '';
    final location = container['location_code'];
    final locationText = location == null || location.toString().isEmpty
        ? ''
        : ' / $location';
    return '$sku / $name: $unitCount x $unitWeight kg = $quantity kg'
        '$locationText';
  }

  double get _knownTotal {
    var total = 0.0;
    for (final row in _parsed?.rows ?? const <OpeningStockRow>[]) {
      final count = row.unitCount;
      final weight = row.unitWeightKg;
      if (count != null && weight != null && count > 0 && weight > 0) {
        total += (count * weight).toDouble();
      }
    }
    return total;
  }

  Map<String, dynamic>? get _summary {
    final response = _dryRun;
    if (response == null) return null;
    final raw = response['summary'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
