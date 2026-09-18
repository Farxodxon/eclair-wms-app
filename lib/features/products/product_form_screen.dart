import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/api_client.dart';
import 'package:wms_app/features/auth/auth_provider.dart';

final categoriesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) {
  final auth = ref.watch(authProvider);
  return auth.token != null
      ? ApiClient().getCategories(auth.token!)
      : Future.value([]);
});

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _minStockController = TextEditingController();
  final _maxStockController = TextEditingController();

  int? _selectedCategoryId;
  Map<String, String> _textValues = {};
  Map<String, bool> _boolValues = {};
  Map<String, DateTime?> _dateValues = {};
  Map<String, TextEditingController> _dynamicControllers = {};
  String? _error;
  bool _saving = false;

  List<dynamic> _currentSchema = [];

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _unitController.dispose();
    _barcodeController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    for (final c in _dynamicControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCategoryChanged(int? categoryId, List<dynamic> schema) {
    setState(() {
      _selectedCategoryId = categoryId;
      _currentSchema = schema;
      _textValues = {};
      _boolValues = {};
      _dateValues = {};
      for (final c in _dynamicControllers.values) {
        c.dispose();
      }
      _dynamicControllers = {};
      _error = null;
    });
  }

  String _labelOf(Map<String, dynamic> attr) {
    final label = attr['label'];
    if (label is String && label.isNotEmpty) return label;
    return attr['key'] as String? ?? '';
  }

  Widget _buildDynamicField(Map<String, dynamic> attr) {
    final key = attr['key'] as String? ?? '';
    final type = attr['type'] as String? ?? 'text';
    final label = _labelOf(attr);

    switch (type) {
      case 'text':
        _dynamicControllers.putIfAbsent(key, () => TextEditingController());
        return TextFormField(
          controller: _dynamicControllers[key],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _textValues[key] = v,
        );
      case 'number':
        _dynamicControllers.putIfAbsent(key, () => TextEditingController());
        return TextFormField(
          controller: _dynamicControllers[key],
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _textValues[key] = v,
        );
      case 'bool':
        return Row(
          children: [
            Expanded(child: Text(label)),
            Switch(
              value: _boolValues[key] ?? false,
              onChanged: (v) => setState(() => _boolValues[key] = v),
            ),
          ],
        );
      case 'date':
        return Row(
          children: [
            Expanded(
              child: Text(
                _dateValues[key] != null
                    ? "$label: ${_dateValues[key]!.toIso8601String().split('T').first}"
                    : label,
              ),
            ),
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dateValues[key] ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _dateValues[key] = picked);
                }
              },
              child: const Text('Tanlash'),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  num? _parseNum(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return num.tryParse(value.trim());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    final attributes = <String, dynamic>{};
    for (final element in _currentSchema) {
      if (element is! Map) continue;
      final key = element['key'] as String?;
      if (key == null) continue;
      final type = element['type'] as String? ?? 'text';
      switch (type) {
        case 'text':
          final v = _dynamicControllers[key]?.text.trim();
          if (v != null && v.isNotEmpty) attributes[key] = v;
          break;
        case 'number':
          final v = _dynamicControllers[key]?.text.trim();
          if (v != null && v.isNotEmpty) {
            final parsed = num.tryParse(v);
            if (parsed == null) {
              setState(() {
                _error = '${element['label'] ?? key}: son bolishi kerak';
              });
              return;
            }
            attributes[key] = parsed;
          }
          break;
        case 'bool':
          attributes[key] = _boolValues[key] ?? false;
          break;
        case 'date':
          final d = _dateValues[key];
          if (d != null) attributes[key] = d.toIso8601String().split('T').first;
          break;
      }
    }

    final body = <String, dynamic>{
      'category_id': _selectedCategoryId,
      'sku': _skuController.text.trim(),
      'name': _nameController.text.trim(),
      'unit': _unitController.text.trim(),
      'attributes': attributes,
    };
    if (_barcodeController.text.trim().isNotEmpty) {
      body['barcode'] = _barcodeController.text.trim();
    }
    final minStock = _parseNum(_minStockController.text);
    final maxStock = _parseNum(_maxStockController.text);
    if (minStock != null) body['min_stock'] = minStock;
    if (maxStock != null) body['max_stock'] = maxStock;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient().createProduct(auth.token!, body);
      if (mounted) Navigator.pop(context);
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
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Mahsulot qoshish")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Kategoriya xatosi: $err'),
              data: (categories) {
                return DropdownButtonFormField<int?>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Kategoriya',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem<int?>(
                        value: c['id'] as int?,
                        child: Text(c['name'] as String? ?? ''),
                      ),
                  ],
                  onChanged: (value) {
                    Map<String, dynamic>? chosen;
                    for (final c in categories) {
                      if ((c as Map)['id'] == value) {
                        chosen = c as Map<String, dynamic>;
                        break;
                      }
                    }
                    final schema = chosen != null
                        ? (chosen['attribute_schema'] as List? ?? [])
                        : <dynamic>[];
                    _onCategoryChanged(value, schema);
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'SKU',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'SKU majburiy' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nomi',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nomi majburiy' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'Birlik (kg, dona...)',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Birlik majburiy' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _barcodeController,
              decoration: const InputDecoration(
                labelText: 'Shtrix-kod (ixtiyoriy)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _minStockController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Min zaxira (ixtiyoriy)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxStockController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Max zaxira (ixtiyoriy)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_currentSchema.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Kategoriya atributlari',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final element in _currentSchema)
                if (element is Map) ...[
                  _buildDynamicField(Map<String, dynamic>.from(element)),
                  const SizedBox(height: 16),
                ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Saqlash'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}